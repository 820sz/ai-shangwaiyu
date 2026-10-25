import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/api_endpoint.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/services/writing_review_settings.dart';

/// 写译批改设置测试(v2.13,用户 2026-10-20 第 3 条)。
///
/// 守住"设置要记住"这条:提示词改完能读回来、改回默认会清掉自定义副本、
/// 思考档位按模型族校验(非法值不写进 Hive,脏数据回默认)。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_writing_settings_test');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('默认提示词', () {
    test('没设置过 → 返回默认提示词,且不是空串', () {
      expect(WritingReviewSettings.prompt(), WritingReviewSettings.defaultPrompt);
      expect(WritingReviewSettings.prompt().trim(), isNotEmpty);
      expect(WritingReviewSettings.isPromptCustomized, isFalse);
    });

    test('默认提示词包含结果页依赖的 JSON 字段', () {
      final p = WritingReviewSettings.defaultPrompt;
      expect(p, contains('"score"'));
      expect(p, contains('"issues"'));
      expect(p, contains('"error_summary"'));
      expect(p, contains('"correction"'));
      expect(p, contains('"summary"'));
    });
  });

  group('提示词持久化', () {
    test('改完保存 → 下次读取拿回自定义内容', () async {
      expect(await WritingReviewSettings.savePrompt('请用雅思标准批改。'), isTrue);
      expect(WritingReviewSettings.prompt(), '请用雅思标准批改。');
      expect(WritingReviewSettings.isPromptCustomized, isTrue);
    });

    test('保存空串/空白 → 视为恢复默认,并删除自定义 key', () async {
      await WritingReviewSettings.savePrompt('自定义');
      expect(await WritingReviewSettings.savePrompt('   '), isTrue);
      expect(WritingReviewSettings.prompt(), WritingReviewSettings.defaultPrompt);
      expect(
        Hive.box(AppConstants.hiveBoxSettings)
            .containsKey(AppConstants.keyWritingReviewPrompt),
        isFalse,
      );
    });

    test('把默认提示词原样存回去 → 不产生自定义副本', () async {
      expect(
        await WritingReviewSettings.savePrompt(WritingReviewSettings.defaultPrompt),
        isTrue,
      );
      expect(WritingReviewSettings.isPromptCustomized, isFalse);
      expect(
        Hive.box(AppConstants.hiveBoxSettings)
            .containsKey(AppConstants.keyWritingReviewPrompt),
        isFalse,
      );
    });
  });

  group('思考档位', () {
    test('默认不思考(与改造前行为一致)', () {
      expect(
        WritingReviewSettings.thinkingFor('doubao-seed-2-0-lite-260428'),
        WritingReviewSettings.defaultThinking,
      );
    });

    test('DeepSeek 模型族可选 max,存进去能读回来', () async {
      const model = 'deepseek-flash';
      expect(await WritingReviewSettings.setThinking(model, 'max'), isTrue);
      expect(WritingReviewSettings.thinkingFor(model), 'max');
    });

    test('豆包族没有 max → 拒绝写入,读取回默认', () async {
      const model = 'doubao-seed-2-0-lite-260428';
      expect(await WritingReviewSettings.setThinking(model, 'max'), isFalse);
      expect(
        WritingReviewSettings.thinkingFor(model),
        WritingReviewSettings.defaultThinking,
      );
    });

    test('Hive 里是脏值/旧档位 → 读取回默认,不炸', () async {
      const model = 'deepseek-flash';
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyWritingReviewThinking, 'medium');
      expect(
        WritingReviewSettings.thinkingFor(model),
        WritingReviewSettings.defaultThinking,
      );
    });

    test('档位显示名:找到用中文标签,找不到原样返回', () {
      expect(
        WritingReviewSettings.thinkingLabel('deepseek-flash', 'max'),
        '极致',
      );
      expect(WritingReviewSettings.thinkingLabel('deepseek-flash', '??'), '??');
    });
  });

  group('批改槽位选择(v2.13 直批手写图要视觉模型)', () {
    late Box box;

    setUp(() {
      box = Hive.box(AppConstants.hiveBoxSettings);
    });

    test('没配副槽位 → 文本批改用主槽位', () {
      expect(
        DoubaoApiService.reviewWritingEndpoint().hiveKey,
        ApiEndpointConfig.primary.hiveKey,
      );
    });

    test('配了副槽位 → 文本批改优先副槽位(便宜快)', () async {
      await box.put(AppConstants.keyDeepseekApiKey, 'sk-test');
      expect(
        DoubaoApiService.reviewWritingEndpoint().hiveKey,
        ApiEndpointConfig.secondary.hiveKey,
      );
    });

    test('副槽位模型不能看图 → 直批手写图回主槽位', () async {
      await box.put(AppConstants.keyDeepseekApiKey, 'sk-test');
      await box.put(AppConstants.keyDeepseekModel, 'deepseek-v4-pro');
      expect(
        DoubaoApiService.reviewWritingEndpoint(requireVision: true).hiveKey,
        ApiEndpointConfig.primary.hiveKey,
      );
    });

    test('副槽位是 deepseek-flash(能吃图)→ 直批用副槽位', () async {
      await box.put(AppConstants.keyDeepseekApiKey, 'sk-test');
      await box.put(AppConstants.keyDeepseekModel, 'deepseek-flash');
      expect(
        DoubaoApiService.reviewWritingEndpoint(requireVision: true).hiveKey,
        ApiEndpointConfig.secondary.hiveKey,
      );
    });
  });
}
