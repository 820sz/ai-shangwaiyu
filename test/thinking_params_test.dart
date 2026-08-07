import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/api_endpoint.dart';

/// 思考参数映射回归测试(2026-08-07):
/// budget_tokens 对豆包无效(实测 27-37s 不受预算控制),
/// 改用 reasoning_effort(实测 minimal≈3s/low≈14s/medium≈25s 复杂图)。
/// 档位映射(用户决策"整体提速档"):低→minimal、中→low、高→medium。
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

  test('medium → reasoning_effort=low', () async {
    final p = await paramsFor('medium');
    expect(p['reasoning_effort'], 'low');
    expect(p.containsKey('budget_tokens'), isFalse);
  });

  test('high → reasoning_effort=medium', () async {
    final p = await paramsFor('high');
    expect(p['reasoning_effort'], 'medium');
    expect(p.containsKey('budget_tokens'), isFalse);
  });

  test('未配置思考 → 默认 disabled', () async {
    final p = await paramsFor('unset_whatever');
    expect(p['thinking'], {'type': 'disabled'});
    expect(p.containsKey('reasoning_effort'), isFalse);
  });

  test('存量档位值仍是合法 key(迁移安全)', () async {
    for (final v in ['disabled', 'low', 'medium', 'high']) {
      final p = await paramsFor(v);
      expect(p, isNotNull);
    }
  });
}
