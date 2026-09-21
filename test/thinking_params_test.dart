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

  // ── v1.3.0:追问独立档位 buildThinkingParamsFor(4 档,非迁移路径) ──

  test('buildThinkingParamsFor(disabled) → thinking.type=disabled', () async {
    final p = ApiEndpointConfig.primary.buildThinkingParamsFor('disabled');
    expect(p['thinking'], {'type': 'disabled'});
    expect(p.containsKey('reasoning_effort'), isFalse);
  });

  test('buildThinkingParamsFor(low) 豆包系 → minimal', () async {
    final p = ApiEndpointConfig.primary.buildThinkingParamsFor('low');
    expect(p['thinking'], {'type': 'enabled'});
    expect(p['reasoning_effort'], 'minimal');
  });

  test('buildThinkingParamsFor(medium/high) 豆包系 → medium/high(不迁移)', () async {
    expect(
      ApiEndpointConfig.primary.buildThinkingParamsFor('medium')['reasoning_effort'],
      'medium',
    );
    expect(
      ApiEndpointConfig.primary.buildThinkingParamsFor('high')['reasoning_effort'],
      'high',
    );
  });

  test('主槽位配 DeepSeek 模型(端点也是官方)→ 官方档位 low/high/max,medium 归一 high', () async {
    final box = Hive.box(AppConstants.hiveBoxSettings);
    // v1.9.0(P2-19):是否"DS 官方端点"改为 baseUrl + 模型名**双条件**判定,
    // 所以这里必须把端点一起配成 DeepSeek 官方 —— 这也正是用户只填 sk- Key
    // 时 baseUrl getter 的自动配对结果(真机路径)。
    await box.put(AppConstants.keyDoubaoBaseUrl, AppConstants.deepseekBaseUrl);
    await box.put(AppConstants.keyDoubaoModel, 'deepseek-v4-flash-vision-exp');
    expect(ApiEndpointConfig.primary.isDeepSeekOfficial, isTrue);
    expect(
      ApiEndpointConfig.primary.buildThinkingParamsFor('low')['reasoning_effort'],
      'low',
    );
    expect(
      ApiEndpointConfig.primary.buildThinkingParamsFor('medium')['reasoning_effort'],
      'high', // DS 官方无 medium → 归一为临近档 high(v1.4.4)
    );
    expect(
      ApiEndpointConfig.primary.buildThinkingParamsFor('high')['reasoning_effort'],
      'high',
    );
    expect(
      ApiEndpointConfig.primary.buildThinkingParamsFor('max')['reasoning_effort'],
      'max', // DS 官方档位含 max
    );
    // 恢复默认豆包模型,避免影响其他测试
    await box.put(AppConstants.keyDoubaoModel, '');
    await box.put(AppConstants.keyDoubaoBaseUrl, '');
  });

  test('方舟端点 + deepseek 模型名 → 仍按方舟参数族,且 max 归一 high(不发非法枚举)', () async {
    final box = Hive.box(AppConstants.hiveBoxSettings);
    await box.put(AppConstants.keyDoubaoBaseUrl, AppConstants.doubaoBaseUrl);
    await box.put(AppConstants.keyDoubaoModel, 'deepseek-v3-1-250821'); // 方舟转售
    final ep = ApiEndpointConfig.primary;
    expect(ep.isDeepSeekOfficial, isFalse); // 端点不是 deepseek.com
    // 方舟族:low → minimal(不是 DS 官方的 low)
    expect(ep.buildThinkingParamsFor('low')['reasoning_effort'], 'minimal');
    // 档位表按模型名给的是 DS 表(含「极致」),但方舟不认 max →
    // 必须归一 high,否则 400 → 降级把思考整个关掉(v1.7.0 老 bug 复现)
    expect(ep.buildThinkingParamsFor('max')['reasoning_effort'], 'high');
    expect(ep.buildThinkingParamsFor('high')['reasoning_effort'], 'high');
    // 表外值仍安全回落不思考
    expect(ep.buildThinkingParamsFor('ultra'), {'thinking': {'type': 'disabled'}});
    await box.put(AppConstants.keyDoubaoModel, '');
    await box.put(AppConstants.keyDoubaoBaseUrl, '');
  });

  test('DS 档位表:官方只有 low/high/max(无 medium)+ 存量 medium 迁移 low', () async {
    expect(AppConstants.deepseekThinkingOptions.keys, [
      'disabled', 'low', 'high', 'max',
    ]);
    final box = Hive.box(AppConstants.hiveBoxSettings);
    await box.put(AppConstants.keyDoubaoModel, 'deepseek-v4-flash-vision-exp');
    await box.put(AppConstants.keyDoubaoThinking, 'medium');
    // thinking getter 对 DS 的 medium → 迁移写回 low(不把非法档发出去)
    expect(ApiEndpointConfig.primary.thinking, 'low');
    expect(box.get(AppConstants.keyDoubaoThinking), 'low');
    // 豆包模型 medium → 迁移 low(2026-08-08 决策)
    await box.put(AppConstants.keyDoubaoModel, '');
    await box.put(AppConstants.keyDoubaoThinking, 'medium');
    expect(ApiEndpointConfig.primary.thinking, 'low');
  });

  // ── v1.7.0 回归:用户实测「选极致变成不思考」 ──

  group('思考档位不再被兜底打回 disabled(v1.7.0)', () {
    Future<void> useDs() async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      // 真机 DS 配置 = sk- Key(端点自动配对 deepseek.com)+ DS 视觉模型
      await box.put(AppConstants.keyDoubaoBaseUrl, AppConstants.deepseekBaseUrl);
      await box.put(
        AppConstants.keyDoubaoModel,
        'deepseek-v4-flash-vision-exp',
      );
    }

    test('DS + max(极致) → thinking getter 原样返回 max(核心 bug 回归)', () async {
      await useDs();
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyDoubaoThinking, 'max');
      expect(ApiEndpointConfig.primary.thinking, 'max');
      expect(box.get(AppConstants.keyDoubaoThinking), 'max'); // 不被改写
      expect(
        ApiEndpointConfig.primary.buildThinkingParams()['reasoning_effort'],
        'max',
      );
    });

    test('DS + high → 原样返回 high(不再被当成非法值)', () async {
      await useDs();
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyDoubaoThinking, 'high');
      expect(ApiEndpointConfig.primary.thinking, 'high');
      expect(box.get(AppConstants.keyDoubaoThinking), 'high');
    });

    test('豆包 + max(自身没有该档) → 回不思考,与设置页显示一致', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyDoubaoModel, '');
      await box.put(AppConstants.keyDoubaoThinking, 'max');
      // 豆包档位表只有 disabled/low;max 属表外值 → 安全回落 disabled。
      // 关键:设置页 _migrateThinking 对同一输入也给 disabled——UI 与请求
      // 行为必须一致(否则又是"显示不思考、实际带思考"的老问题)。
      expect(ApiEndpointConfig.primary.thinking, 'disabled');
    });

    test('豆包 + 存量 medium/high → 迁移 low 并写回(2026-08-08 两档决策)', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyDoubaoModel, '');
      for (final legacy in ['medium', 'high']) {
        await box.put(AppConstants.keyDoubaoThinking, legacy);
        expect(ApiEndpointConfig.primary.thinking, 'low');
        expect(box.get(AppConstants.keyDoubaoThinking), 'low');
      }
    });

    test('追问档位表按模型族区分:DS 无 medium,含 max', () {
      expect(
        AppConstants.followUpThinkingOptionsFor('deepseek-v4-flash').keys,
        ['disabled', 'low', 'high', 'max'],
      );
      expect(
        AppConstants.followUpThinkingOptionsFor('doubao-seed-1-6').keys,
        ['disabled', 'low', 'medium', 'high'],
      );
      expect(AppConstants.deepseekThinkingOptions['max'], '极致');
    });
  });
}
