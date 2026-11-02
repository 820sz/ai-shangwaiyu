import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/learner_model_store.dart';
import 'package:readflow/services/material_prefs.dart';

/// 批 2(C1-18 / C1-2 前置)输入偏好统一模型层的回归测试。
///
/// 这里守的东西都是"以后改 UI 时最容易悄悄改错"的口径:
/// 1. 难度档字符串必须与 `MaterialBand` 的真实 Hive 取值一一对应(不能猜);
/// 2. 覆盖率边界(0.98 / 0.90)**直接复用 `MaterialBand`**,不另立数字,且 i+1 不能排除更容易读的材料;
/// 3. 目标多选 → 单值回退的解析(访谈存的是 `四六级(半年内)` 这种复合串);
/// 4. 黑名单是"包含匹配 + 忽略大小写",且标题/来源/题材都能命中;
/// 5. `suggestBand` 的数据不足/信号冲突/端点情况**必须返回 null**(不猜);
/// 6. `load()` 对 Hive 脏数据、缺字段不崩;`saveBand()` 不破坏其它偏好字段。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DifficultyBand 与既有字符串一一映射', () {
    test('rawValue 就是 MaterialBand.name(真实 Hive 取值,不是猜的)', () {
      expect(DifficultyBand.comfortable.rawValue, 'i1');
      expect(DifficultyBand.challenge.rawValue, 'i10');
      expect(DifficultyBand.fastGain.rawValue, 'i100');
      expect(DifficultyBand.any.rawValue, 'any');

      expect(DifficultyBand.comfortable.materialBand, MaterialBand.i1);
      expect(DifficultyBand.challenge.materialBand, MaterialBand.i10);
      expect(DifficultyBand.fastGain.materialBand, MaterialBand.i100);
      expect(DifficultyBand.any.materialBand, MaterialBand.any);
    });

    test('每个档位 rawValue → bandOf 往返一致', () {
      for (final band in DifficultyBand.values) {
        expect(DifficultyBand.bandOf(band.rawValue), band,
            reason: '${band.rawValue} 往返必须一致');
      }
    });

    test('大小写 / 本层枚举名也认(写回与测试直传都能用)', () {
      expect(DifficultyBand.bandOf('I10'), DifficultyBand.challenge);
      expect(DifficultyBand.bandOf('i100'), DifficultyBand.fastGain);
      expect(DifficultyBand.bandOf('comfortable'), DifficultyBand.comfortable);
      expect(DifficultyBand.bandOf(' any '), DifficultyBand.any);
    });

    test('脏值/空串回退 comfortable(用户默认最安全:宁可简单,不要过难)', () {
      expect(DifficultyBand.bandOf(''), DifficultyBand.comfortable);
      expect(DifficultyBand.bandOf('garbage'), DifficultyBand.comfortable);
      expect(DifficultyBand.bandOf('i+1'), DifficultyBand.comfortable);
      expect(DifficultyBand.bandOf('  '), DifficultyBand.comfortable);
    });

    test('用户语义文案:i+100 不得写成负面(费劲但爽 / 短期冲量)', () {
      expect(DifficultyBand.comfortable.label, contains('i+1'));
      expect(DifficultyBand.challenge.label, contains('i+10'));
      expect(DifficultyBand.fastGain.label, contains('i+100'));
      expect(DifficultyBand.fastGain.description, contains('费劲但爽'));
      expect(DifficultyBand.fastGain.description, contains('短期冲量'));
      expect(DifficultyBand.any.description, contains('不做难度约束'));
    });
  });

  group('覆盖率边界(0.98 / 0.90,与 MaterialBand 同口径)', () {
    test('i+10 是 [0.90,0.98):0.90 归它,0.98 不归', () {
      expect(coverageInBand(0.90, DifficultyBand.challenge), isTrue);
      expect(coverageInBand(0.979, DifficultyBand.challenge), isTrue);
      expect(coverageInBand(0.98, DifficultyBand.challenge), isFalse);
    });

    test('i+1 是 ≥0.98:0.98 / 0.99 / 1.0 都算(更容易读的也属于 i+1)', () {
      for (final c in [0.98, 0.99, 1.0]) {
        expect(coverageInBand(c, DifficultyBand.comfortable), isTrue,
            reason: '覆盖率 $c 属于 i+1');
      }
      expect(coverageInBand(0.979, DifficultyBand.comfortable), isFalse);
    });

    test('i+100 是 <0.90:0.90 已归 i+10', () {
      expect(coverageInBand(0.0, DifficultyBand.fastGain), isTrue);
      expect(coverageInBand(0.899, DifficultyBand.fastGain), isTrue);
      expect(coverageInBand(0.90, DifficultyBand.fastGain), isFalse);
    });

    test('不限档恒真;NaN 一律 false;越界值先夹到 [0,1]', () {
      for (final c in [0.0, 0.3, 0.9, 1.0]) {
        expect(coverageInBand(c, DifficultyBand.any), isTrue);
      }
      expect(coverageInBand(double.nan, DifficultyBand.comfortable), isFalse);
      expect(coverageInBand(double.nan, DifficultyBand.any), isFalse);
      expect(coverageInBand(1.2, DifficultyBand.comfortable), isTrue);
      expect(coverageInBand(-0.5, DifficultyBand.fastGain), isTrue);
    });

    test('ofCoverage:材料属于哪档(any 不参与)', () {
      expect(DifficultyBand.ofCoverage(0.99), DifficultyBand.comfortable);
      expect(DifficultyBand.ofCoverage(0.98), DifficultyBand.comfortable);
      expect(DifficultyBand.ofCoverage(0.979), DifficultyBand.challenge);
      expect(DifficultyBand.ofCoverage(0.90), DifficultyBand.challenge);
      expect(DifficultyBand.ofCoverage(0.899), DifficultyBand.fastGain);
      expect(DifficultyBand.ofCoverage(double.nan), isNull);
    });

    test('区间不另立数字:coverageMin/Max 与 MaterialBand 完全一致', () {
      expect(DifficultyBand.comfortable.coverageMin, MaterialBand.i1.min);
      expect(DifficultyBand.comfortable.coverageMax, MaterialBand.i1.max);
      expect(DifficultyBand.challenge.coverageMin, MaterialBand.i10.min);
      expect(DifficultyBand.challenge.coverageMax, MaterialBand.i10.max);
      expect(DifficultyBand.fastGain.coverageMin, MaterialBand.i100.min);
      expect(DifficultyBand.fastGain.coverageMax, MaterialBand.i100.max);
    });
  });

  group('examGoals:多选优先、单值回退解析', () {
    test('goals 非空时直接用 goals', () {
      final p = InputPreferences.fromSources(
        model: LearnerModel(goals: ['四六级', '兴趣阅读']),
      );
      expect(p.examGoals, ['四六级', '兴趣阅读']);
    });

    test('goals 为空时解析 goal 复合串:四六级(半年内) → 四六级', () {
      final p = InputPreferences.fromSources(
        model: LearnerModel(
          goal: ProfileField<String>(
            value: '四六级(半年内)',
            source: ProfileSource.self,
          ),
        ),
      );
      expect(p.examGoals, ['四六级']);
    });

    test('goal 用 + / 、 拼多目标也能拆;不按 / 拆(雅思/托福是一个档位名)', () {
      final p1 = InputPreferences.fromSources(
        model: LearnerModel(
          goal: ProfileField<String>(
            value: '四六级 + 兴趣阅读',
            source: ProfileSource.self,
          ),
        ),
      );
      expect(p1.examGoals, ['四六级', '兴趣阅读']);

      final p2 = InputPreferences.fromSources(
        model: LearnerModel(
          goal: ProfileField<String>(
            value: '雅思/托福(3 个月内)',
            source: ProfileSource.self,
          ),
        ),
      );
      expect(p2.examGoals, ['雅思/托福'], reason: '雅思/托福不能被拆成两个假目标');
    });

    test('都为空 → 空列表;重复项去重', () {
      expect(InputPreferences.fromSources().examGoals, isEmpty);
      final p = InputPreferences.fromSources(
        model: LearnerModel(goals: ['四六级', '四六级 ', '']),
      );
      expect(p.examGoals, ['四六级']);
    });
  });

  group('interests:两个来源合并去重', () {
    test('interests ∪ genres(自由文本按顿号/逗号拆)', () {
      final p = InputPreferences.fromSources(
        model: LearnerModel(
          interests: ProfileField<List<String>>(
            value: ['科普科技', '小说故事'],
            source: ProfileSource.self,
          ),
        ),
        prefs: const MaterialPrefs(genres: '小说故事、商业财经,历史文化'),
      );
      expect(p.interests, ['科普科技', '小说故事', '商业财经', '历史文化']);
    });

    test('忽略大小写去重(英文兴趣名不重复),空格不拆', () {
      final p = InputPreferences.fromSources(
        model: LearnerModel(
          interests: ProfileField<List<String>>(
            value: ['Science'],
            source: ProfileSource.self,
          ),
        ),
        prefs: const MaterialPrefs(genres: 'science、science fiction'),
      );
      expect(p.interests, ['Science', 'science fiction']);
    });
  });

  group('黑名单过滤 allowsMaterial(包含匹配 + 忽略大小写)', () {
    InputPreferences withBlocks({
      List<String> topics = const [],
      List<String> keywords = const [],
    }) =>
        InputPreferences(blockedTopics: topics, blockedKeywords: keywords);

    test('没有黑名单 → 恒 true', () {
      final p = withBlocks();
      expect(
        p.allowsMaterial(title: '任何东西', source: 'NPR', genres: const ['新闻']),
        isTrue,
      );
    });

    test('关键词命中标题 → 挡掉;命中来源也挡;命中题材也挡', () {
      final p = withBlocks(keywords: ['政治', 'NPR']);
      expect(p.allowsMaterial(title: '政治经济学入门', source: null, genres: const []),
          isFalse);
      expect(p.allowsMaterial(title: 'Economy', source: 'NPR News', genres: const []),
          isFalse);
      expect(p.allowsMaterial(title: 'Economy', source: null, genres: const ['政治']),
          isFalse);
      expect(p.allowsMaterial(title: 'Biology 101', source: 'arXiv', genres: const ['科学']),
          isTrue);
    });

    test('题材黑名单命中 genres / 标题 → 挡掉', () {
      final p = withBlocks(topics: ['恐怖']);
      expect(p.allowsMaterial(title: 'Horror Story', source: null, genres: const ['恐怖小说']),
          isFalse);
      expect(p.allowsMaterial(title: '恐怖故事集', source: null, genres: const []),
          isFalse);
      expect(p.allowsMaterial(title: 'Cook Book', source: null, genres: const ['生活']),
          isTrue);
    });

    test('黑名单值首尾空白/大小写不影响命中', () {
      final p = withBlocks(keywords: ['  npr ']);
      expect(p.allowsMaterial(title: 'News', source: 'NPR News', genres: const []),
          isFalse);
    });

    test('黑名单项为空串时不算命中(脏数据不能屏蔽一切)', () {
      final p = withBlocks(keywords: ['', '   '], topics: ['']);
      expect(p.allowsMaterial(title: 'Anything', source: null, genres: const []),
          isTrue);
    });
  });

  group('suggestBand:数据不足/冲突不猜,有证据才给升降档', () {
    test('全 null → null(不猜)', () {
      expect(
        suggestBand(
          finishedRatio: null,
          avgLookupPer100: null,
          quizAccuracy: null,
          current: DifficultyBand.challenge,
        ),
        isNull,
      );
    });

    test('只有一个指标 → null(数据不足)', () {
      expect(
        suggestBand(
          finishedRatio: 0.1,
          avgLookupPer100: null,
          quizAccuracy: null,
          current: DifficultyBand.challenge,
        ),
        isNull,
      );
    });

    test('两个指标一降一中(无明确信号) → null', () {
      expect(
        suggestBand(
          finishedRatio: 0.3, // 降信号
          avgLookupPer100: 7, // 中性
          quizAccuracy: null,
          current: DifficultyBand.challenge,
        ),
        isNull,
      );
    });

    test('两个降档信号 → 建议降档,文案带真实数字与目标档', () {
      final s = suggestBand(
        finishedRatio: 0.32,
        avgLookupPer100: 18,
        quizAccuracy: null,
        current: DifficultyBand.challenge,
      );
      expect(s, isNotNull);
      expect(s!.band, DifficultyBand.comfortable);
      expect(s.text, contains('32%'));
      expect(s.text, contains('降'));
      expect(s.text, contains('i+1'));
    });

    test('两个升档信号 → 建议升档(comfortable → challenge)', () {
      final s = suggestBand(
        finishedRatio: 0.92,
        avgLookupPer100: 1.5,
        quizAccuracy: 0.9,
        current: DifficultyBand.comfortable,
      );
      expect(s, isNotNull);
      expect(s!.band, DifficultyBand.challenge);
      expect(s.text, contains('升'));
      expect(s.text, contains('i+10'));
    });

    test('信号冲突(1 降 1 升) → null,不硬给结论', () {
      expect(
        suggestBand(
          finishedRatio: 0.3,
          avgLookupPer100: null,
          quizAccuracy: 0.95,
          current: DifficultyBand.challenge,
        ),
        isNull,
      );
    });

    test('3 个指标 2 降 1 升 → 按多数建议降档(fastGain → challenge)', () {
      final s = suggestBand(
        finishedRatio: 0.2,
        avgLookupPer100: 20,
        quizAccuracy: 0.95,
        current: DifficultyBand.fastGain,
      );
      expect(s, isNotNull);
      expect(s!.band, DifficultyBand.challenge);
    });

    test('current = any → null(没有当前档可比)', () {
      expect(
        suggestBand(
          finishedRatio: 0.1,
          avgLookupPer100: 20,
          quizAccuracy: 0.2,
          current: DifficultyBand.any,
        ),
        isNull,
      );
    });

    test('已在最简单档还提示降档 / 已在最难档还提示升档 → null(没有可去的档)', () {
      expect(
        suggestBand(
          finishedRatio: 0.1,
          avgLookupPer100: 20,
          quizAccuracy: null,
          current: DifficultyBand.comfortable,
        ),
        isNull,
      );
      expect(
        suggestBand(
          finishedRatio: 0.95,
          avgLookupPer100: 0.5,
          quizAccuracy: null,
          current: DifficultyBand.fastGain,
        ),
        isNull,
      );
    });

    test('NaN 指标视为缺失(不与其它指标拼成假结论)', () {
      expect(
        suggestBand(
          finishedRatio: double.nan,
          avgLookupPer100: null,
          quizAccuracy: 0.3,
          current: DifficultyBand.challenge,
        ),
        isNull,
      );
    });
  });

  group('promptHint:给 AI 检索规划的一句话', () {
    test('结构化包含 目标 / 难度 / 兴趣 / 避开', () {
      final p = InputPreferences.fromSources(
        model: LearnerModel(
          goals: ['四六级'],
          interests: ProfileField<List<String>>(
            value: ['科普科技'],
            source: ProfileSource.self,
          ),
          blockedKeywords: ['八卦'],
          dailyMinutes: ProfileField<int>(
            value: 30,
            source: ProfileSource.self,
          ),
        ),
        prefs: const MaterialPrefs(
          band: MaterialBand.i10,
          extra: '不要学术腔',
        ),
      );
      final hint = p.promptHint;
      expect(hint, contains('目标'));
      expect(hint, contains('四六级'));
      expect(hint, contains('难度'));
      expect(hint, contains('i+10'));
      expect(hint, contains('兴趣题材'));
      expect(hint, contains('科普科技'));
      expect(hint, contains('避开'));
      expect(hint, contains('八卦'));
      expect(hint, contains('不要学术腔'));
      expect(hint, contains('30 分钟'));
      expect(hint.endsWith('。'), isTrue);
    });

    test('什么都没设置时给可执行兜底(不是空串)', () {
      final hint = InputPreferences.fromSources().promptHint;
      expect(hint, isNotEmpty);
      expect(hint, contains('暂无个性化偏好'));
      expect(hint, contains('难度'));
    });
  });

  group('load / saveBand(Hive 读写,含脏数据容错)', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('input_prefs_test');
      Hive.init(hiveDir.path);
      await Hive.openBox(AppConstants.hiveBoxSettings);
    });

    tearDown(() async {
      try {
        await Hive.deleteFromDisk();
      } catch (_) {}
      try {
        hiveDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('load 读既有两处存储:goal/难度/兴趣/黑名单/时间/来源类型', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(
        AppConstants.keyMaterialPrefs,
        jsonEncode(const MaterialPrefs(
          band: MaterialBand.i10,
          kinds: {'paper'},
          genres: '哲学、幽默',
          extra: '每篇别超过 10 分钟',
        ).toJson()),
      );
      await box.put(
        LearnerModelStore.key,
        LearnerModel(
          goals: ['四六级', '兴趣阅读'],
          interests: ProfileField<List<String>>(
            value: ['科普科技'],
            source: ProfileSource.self,
          ),
          blockedTopics: ['政治新闻'],
          blockedKeywords: ['八卦'],
          dailyMinutes: ProfileField<int>(
            value: 30,
            source: ProfileSource.self,
          ),
        ).toJson(),
      );

      final p = InputPreferences.load();
      expect(p.band, DifficultyBand.challenge);
      expect(p.examGoals, ['四六级', '兴趣阅读']);
      expect(p.interests, ['科普科技', '哲学', '幽默']);
      expect(p.blockedTopics, ['政治新闻']);
      expect(p.blockedKeywords, ['八卦']);
      expect(p.dailyMinutes, 30);
      expect(p.kinds, {'paper'});
      expect(p.extraNeed, '每篇别超过 10 分钟');
      expect(p.isEmpty, isFalse);
    });

    test('load 遇到坏数据不崩:非 JSON / 非 Map 一律当没设置', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyMaterialPrefs, 'not-json{{{');
      await box.put(LearnerModelStore.key, 'not-a-map');

      final p = InputPreferences.load();
      expect(p.band, DifficultyBand.any);
      expect(p.examGoals, isEmpty);
      expect(p.interests, isEmpty);
      expect(p.isEmpty, isTrue);
      expect(p.promptHint, contains('暂无个性化偏好'));
    });

    test('saveBand 写回 material_prefs,并保留其它偏好字段', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(
        AppConstants.keyMaterialPrefs,
        jsonEncode(const MaterialPrefs(
          band: MaterialBand.i10,
          kinds: {'paper'},
          genres: '哲学',
        ).toJson()),
      );

      final p = InputPreferences.load();
      await p.saveBand(DifficultyBand.fastGain);

      final saved = MaterialPrefs.load();
      expect(saved.band, MaterialBand.i100, reason: '写回的是真实 Hive 取值 i100');
      expect(saved.kinds, {'paper'}, reason: '只改 band,不能碰其它偏好');
      expect(saved.genres, '哲学');
      expect(InputPreferences.load().band, DifficultyBand.fastGain);
    });

    test('saveBand(any) 写回不限档', () async {
      await InputPreferences.load().saveBand(DifficultyBand.any);
      expect(MaterialPrefs.load().band, MaterialBand.any);
      expect(InputPreferences.load().band, DifficultyBand.any);
    });
  });
}
