import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/learner_model_store.dart';

/// 学习者模型 v2.0 回归测试。
///
/// 重点守护三件事(它们是 2.0 "专业评估"的地基,退化回去就又变成瞎猜):
/// 1. **来源与置信度必须随字段存取** —— 自报与测量不能混为一谈;
/// 2. **v1.8 的老画像要能迁移**,且迁移后标成 `self`(不是 `test`);
/// 3. **字段能被清空** —— copyWith 的 `??` 兜底曾让"清掉目标"变成不可能。
void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_learner_model_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  group('ProfileField', () {
    test('来源/置信度/时间戳往返不丢', () {
      final f = ProfileField<int>(
        value: 4200,
        source: ProfileSource.test,
        confidence: 0.83,
        updatedAt: DateTime(2026, 9, 22, 10, 30),
      );
      final back = ProfileField.fromJson<int>(f.toJson(), (v) => v as int?)!;
      expect(back.value, 4200);
      expect(back.source, ProfileSource.test);
      expect(back.confidence, closeTo(0.83, 1e-9));
      expect(back.updatedAt, DateTime(2026, 9, 22, 10, 30));
    });

    test('未知来源字符串回落到 self(不能抛异常)', () {
      final back = ProfileField.fromJson<int>(
        {'value': 10, 'source': 'whatever', 'confidence': 5},
        (v) => v as int?,
      )!;
      expect(back.source, ProfileSource.self);
      expect(back.confidence, 1.0, reason: '置信度必须 clamp 到 0..1');
    });

    test('值解析失败 → 返回 null(坏数据不生成字段)', () {
      expect(ProfileField.fromJson<int>({'value': 'x'}, (v) => v as int?), isNull);
      expect(ProfileField.fromJson<int>('not a map', (v) => v as int?), isNull);
    });
  });

  group('LearnerModel', () {
    test('完整往返:词汇量/区间/目标/时间/黑名单/扩展位', () {
      final m = LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 6800,
          source: ProfileSource.test,
          confidence: 0.9,
        ),
        vocabLow: 6100,
        vocabHigh: 7500,
        cefr: ProfileField<String>(
          value: 'C1',
          source: ProfileSource.test,
          confidence: 0.85,
        ),
        lastPlacementAt: DateTime(2026, 9, 22),
        falseAlarmRate: 0.08,
        goal: ProfileField<String>(
          value: '读懂原版书',
          source: ProfileSource.self,
          confidence: 0.6,
        ),
        dailyMinutes: ProfileField<int>(
          value: 45,
          source: ProfileSource.self,
          confidence: 0.7,
        ),
        interests: ProfileField<List<String>>(
          value: const ['小说故事', '科普科技'],
          source: ProfileSource.self,
          confidence: 0.6,
        ),
        blockedTopics: const ['影视娱乐'],
        blockedKeywords: const ['政治'],
        extras: const {'reading_wpm': 210},
      );

      final back = LearnerModel.fromJson(m.toJson());
      expect(back.vocab, 6800);
      expect(back.vocabLow, 6100);
      expect(back.vocabHigh, 7500);
      expect(back.cefr!.value, 'C1');
      expect(back.cefr!.source, ProfileSource.test);
      expect(back.goal!.value, '读懂原版书');
      expect(back.dailyMinutes!.value, 45);
      expect(back.interests!.value, ['小说故事', '科普科技']);
      expect(back.blockedTopics, ['影视娱乐']);
      expect(back.blockedKeywords, ['政治']);
      expect(back.extras['reading_wpm'], 210);
      expect(back.falseAlarmRate, closeTo(0.08, 1e-9));
      expect(back.hasVocabBaseline, isTrue);
    });

    test('坏 JSON 不抛异常(整页不能因为一条坏记录崩掉)', () {
      final back = LearnerModel.fromJson({
        'vocab_estimate': 'garbage',
        'cefr': 42,
        'interests': 'not a list',
        'blocked_topics': null,
        'extras': 7,
      });
      expect(back.vocab, isNull);
      expect(back.cefr, isNull);
      expect(back.interests, isNull);
      expect(back.blockedTopics, isEmpty);
      expect(back.extras, isEmpty);
      expect(back.hasVocabBaseline, isFalse);
    });

    test('missingFields 就是导师该问的问题(顺序固定)', () {
      expect(LearnerModel().missingFields, [
        '词汇量基线(建议做一次词汇量测试)',
        '学习目的',
        '每天可投入时间',
        '偏好题材',
      ]);
      final complete = LearnerModel(
        vocabEstimate: ProfileField<int>(value: 3000, source: ProfileSource.test),
        goal: ProfileField<String>(value: '应试提分', source: ProfileSource.self),
        dailyMinutes: ProfileField<int>(value: 30, source: ProfileSource.self),
        interests: ProfileField<List<String>>(
          value: const ['新闻时事'],
          source: ProfileSource.self,
        ),
      );
      expect(complete.missingFields, isEmpty);
    });

    test('source 会出现在给 AI 的摘要里(不让模型把自报当测量)', () {
      final m = LearnerModel(
        vocabEstimate: ProfileField<int>(value: 2500, source: ProfileSource.test),
        goal: ProfileField<String>(value: '工作邮件', source: ProfileSource.self),
        blockedKeywords: const ['娱乐八卦'],
      );
      expect(m.summaryText, contains('2500'));
      expect(m.summaryText, contains('[test]'));
      expect(m.summaryText, contains('工作邮件'));
      expect(m.summaryText, contains('娱乐八卦'));
      expect(LearnerModel().summaryText, '(用户尚未建立学习画像)');
    });

    test('每日配额字段往返(每日分钟数 + 每日新词上限)', () {
      final m = LearnerModel(
        dailyMinutes: ProfileField<int>(value: 45, source: ProfileSource.self),
        maxNewWords: ProfileField<int>(value: 0, source: ProfileSource.self),
      );
      final back = LearnerModel.fromJson(m.toJson());
      expect(back.dailyMinutes!.value, 45);
      expect(back.maxNewWords!.value, 0, reason: '0 是合法值(只复习不加新词)');
      expect(back.summaryText, contains('每日新词上限:0'));
    });

    test('每日配额能写入也能清空(设置页要能改回去)', () async {
      final base = LearnerModel(
        dailyMinutes: ProfileField<int>(value: 15, source: ProfileSource.self),
      );
      final set = await LearnerModelStore.saveSelfReported(
        base: base,
        dailyMinutes: 60,
        maxNewWords: 10,
      );
      expect(set.dailyMinutes!.value, 60);
      expect(set.maxNewWords!.value, 10);
      expect(set.maxNewWords!.source, ProfileSource.self);

      // 负数 = 未设置(清空);0 仍然是合法值
      final cleared = await LearnerModelStore.saveSelfReported(
        base: set,
        maxNewWords: -1,
      );
      expect(cleared.maxNewWords, isNull);
      final zero = await LearnerModelStore.saveSelfReported(
        base: cleared,
        maxNewWords: 0,
      );
      expect(zero.maxNewWords!.value, 0);
    });

    test('clearXxx 开关能真的清空字段(而不是被 ?? 兜回旧值)', () {
      final m = LearnerModel(
        cefr: ProfileField<String>(value: 'B2', source: ProfileSource.self),
        goal: ProfileField<String>(value: '口语交流', source: ProfileSource.self),
      );
      final cleared = m.copyWith(clearGoal: true);
      expect(cleared.goal, isNull);
      expect(cleared.cefr!.value, 'B2', reason: '只清指定字段,其余保留');
    });
  });

  group('LearnerModelStore', () {
    test('首次读取就把 v1.8 老画像迁成 self 来源(不是 test)', () async {
      await Hive.box(AppConstants.hiveBoxSettings).put(
        LearnerModelStore.legacyKey,
        {
          'level': '中级（B1-B2）',
          'goal': '读懂原版书',
          'interests': ['小说故事'],
          'note': '每天能读半小时',
          'confirmed': true,
        },
      );

      final m = LearnerModelStore.load();
      expect(m.cefr!.value, '中级（B1-B2）');
      expect(m.cefr!.source, ProfileSource.self);
      expect(m.cefr!.confidence, lessThan(0.8),
          reason: '自评水平不能给高置信度');
      expect(m.goal!.value, '读懂原版书');
      expect(m.interests!.value, ['小说故事']);
      expect(m.extras['legacy_note'], '每天能读半小时');
      expect(m.hasVocabBaseline, isFalse, reason: '老版本没有词汇量基线');

      // 迁移结果落库 → 第二次读取直接命中 v2 键
      expect(
        Hive.box(AppConstants.hiveBoxSettings).get(LearnerModelStore.key),
        isNotNull,
      );
      expect(LearnerModelStore.load().cefr!.value, '中级（B1-B2）');
    });

    test('savePlacement:词汇量/区间/CEFR 记为 test,自评偏差拉低置信度', () async {
      final base = LearnerModel(
        goal: ProfileField<String>(value: '应试提分', source: ProfileSource.self),
      );
      final m = await LearnerModelStore.savePlacement(
        base: base,
        estimate: 4800,
        low: 4200,
        high: 5400,
        cefr: 'B2',
        falseAlarmRate: 0.0,
        at: DateTime(2026, 9, 22, 12),
      );

      expect(m.vocab, 4800);
      expect(m.vocabLow, 4200);
      expect(m.vocabHigh, 5400);
      expect(m.cefr!.value, 'B2');
      expect(m.cefr!.source, ProfileSource.test);
      expect(m.vocabEstimate!.source, ProfileSource.test);
      expect(m.vocabEstimate!.confidence, closeTo(0.9, 1e-9));
      expect(m.lastPlacementAt, DateTime(2026, 9, 22, 12));
      expect(m.goal!.value, '应试提分', reason: '测量不应清掉用户自报的其它字段');

      // 伪词误报率高 → 置信度必须下降
      final noisy = await LearnerModelStore.savePlacement(
        base: base,
        estimate: 9000,
        low: 7000,
        high: 11000,
        cefr: 'C1',
        falseAlarmRate: 0.35,
      );
      expect(noisy.vocabEstimate!.confidence, closeTo(0.55, 1e-9));
    });

    test('saveSelfReported:能写入,也能用空串清空(设置页要能改回去)', () async {
      final base = LearnerModel(
        goal: ProfileField<String>(value: '口语交流', source: ProfileSource.self),
      );
      final set = await LearnerModelStore.saveSelfReported(
        base: base,
        goal: '',
        dailyMinutes: 60,
        interests: const ['新闻时事'],
        blockedTopics: const ['影视娱乐'],
        blockedKeywords: const ['八卦'],
      );
      expect(set.goal, isNull, reason: '空串 = 用户清掉了目标');
      expect(set.dailyMinutes!.value, 60);
      expect(set.dailyMinutes!.source, ProfileSource.self);
      expect(set.interests!.value, ['新闻时事']);
      expect(set.blockedTopics, ['影视娱乐']);
      expect(set.blockedKeywords, ['八卦']);
    });
  });
}
