import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/api_endpoint.dart';

/// 思考参数映射回归测试(2026-08-07 初版,2026-08-08 更新):
/// budget_tokens 对豆包无效(实测 27-37s 不受预算控制),
/// 改用 reasoning_effort(实测 minimal≈3s/low≈14s/medium≈25s 复杂图)。
/// 2026-08-08 用户决策:识图只留 不思考/低度 两档——中/高砍掉,
/// 存量 medium/high 设置自动迁移到 low(=minimal)。
void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_thinking_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> paramsFor(String thinking) async {
    final box = Hive.box(AppConstants.hiveBoxSettings);
    await box.put(AppConstants.keyDoubaoThinking, thinking);
    return ApiEndpointConfig.primary.buildThinkingParams();
  }

  test('disabled → thinking.type=disabled,无 reasoning_effort', () async {
    final p = await paramsFor('disabled');
    expect(p['thinking'], {'type': 'disabled'});
    expect(p.containsKey('reasoning_effort'), isFalse);
    expect(p.containsKey('budget_tokens'), isFalse);
  });

  test('low → reasoning_effort=minimal(整体提速档)', () async {
    final p = await paramsFor('low');
    expect(p['thinking'], {'type': 'enabled'});
    expect(p['reasoning_effort'], 'minimal');
    expect(p.containsKey('budget_tokens'), isFalse);
  });

  test('存量 medium → 自动迁移为 low(=minimal)', () async {
    final p = await paramsFor('medium');
    expect(p['thinking'], {'type': 'enabled'});
    expect(p['reasoning_effort'], 'minimal');
    expect(p.containsKey('budget_tokens'), isFalse);
  });

  test('存量 high → 自动迁移为 low(=minimal)', () async {
    final p = await paramsFor('high');
    expect(p['reasoning_effort'], 'minimal');
    expect(p.containsKey('budget_tokens'), isFalse);
  });

  test('未配置思考 → 默认 disabled', () async {
    final p = await paramsFor('unset_whatever');
    expect(p['thinking'], {'type': 'disabled'});
    expect(p.containsKey('reasoning_effort'), isFalse);
  });

  test('存量档位值迁移安全(medium/high 不报错)', () async {
    for (final v in ['disabled', 'low', 'medium', 'high']) {
      final p = await paramsFor(v);
      expect(p, isNotNull);
    }
  });
}
