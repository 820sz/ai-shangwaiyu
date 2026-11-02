import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/learner_model_store.dart';

/// 批 4 · 需求多选的落库回归(用户 2026-11-01:"这些要支持多选呀,
/// 学习者又不是只有一个需求")。
///
/// 守两件事:
/// 1. `saveSelfReported(goals:)` 真的写进 `LearnerModel.goals`(旧实现没有这个参数,
///    访谈只写单值 `goal`,`goals` 永远是空 —— 练习中心与材料推荐都读不到多选目标);
/// 2. `goals: []` 能清空(不是被 `??` 兜底成旧值)。
void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_interview_goals_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  test('多选目标:四六级 + 兴趣阅读 一起写入并读回', () async {
    final base = LearnerModel();
    final saved = await LearnerModelStore.saveSelfReported(
      base: base,
      goals: const ['四六级', '兴趣阅读'],
      goal: '四六级(半年内)',
    );
    expect(saved.goals, ['四六级', '兴趣阅读']);

    final loaded = LearnerModelStore.load();
    expect(loaded.goals, ['四六级', '兴趣阅读']);
    // 单值 goal 仍然兼容写(旧读者/AI 提示词还在用它)
    expect(loaded.goal?.value, '四六级(半年内)');
  });

  test('传空列表能真的清空 goals(copyWith 的 ?? 兜底不会把它救回来)', () async {
    await LearnerModelStore.saveSelfReported(
      base: LearnerModel(),
      goals: const ['考研', '雅思/托福'],
    );
    expect(LearnerModelStore.load().goals.length, 2);

    await LearnerModelStore.saveSelfReported(
      base: LearnerModelStore.load(),
      goals: const [],
    );
    expect(LearnerModelStore.load().goals, isEmpty);
  });

  test('不传 goals = 不改动(其它字段的保存不会误清目标)', () async {
    await LearnerModelStore.saveSelfReported(
      base: LearnerModel(),
      goals: const ['四六级'],
    );
    await LearnerModelStore.saveSelfReported(
      base: LearnerModelStore.load(),
      dailyMinutes: 30,
    );
    final loaded = LearnerModelStore.load();
    expect(loaded.goals, ['四六级']);
    expect(loaded.dailyMinutes?.value, 30);
  });
}
