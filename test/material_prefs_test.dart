import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_prefs.dart';
import 'package:readflow/services/material_source.dart';

/// v2.7 材料偏好与难度档的单测(用户第 4、5 条)。
///
/// 为什么值得单测:这两样东西直接影响"AI 去找什么材料"与"材料库怎么排序",
/// 而它们的错法都很安静 —— 区间写重了(i+1 与 i+10 都命中)、脏 JSON 把偏好读崩、
/// 类型偏好映射到不存在的源导致空结果。这些在界面上表现为"偏好好像没生效",
/// 用户无从判断是没生效还是本来就没有合适材料,所以必须在测试里钉死。
void main() {
  group('MaterialBand(难度档)', () {
    test('三个档的区间互不重叠、覆盖 0~1(边界 0.98 归 i+1、0.90 归 i+10)', () {
      expect(MaterialBand.i1.contains(0.99), isTrue);
      expect(MaterialBand.i1.contains(0.98), isTrue);
      expect(MaterialBand.i1.contains(0.979), isFalse);

      expect(MaterialBand.i10.contains(0.98), isFalse);
      expect(MaterialBand.i10.contains(0.979), isTrue);
      expect(MaterialBand.i10.contains(0.95), isTrue);
      expect(MaterialBand.i10.contains(0.90), isTrue);
      expect(MaterialBand.i10.contains(0.899), isFalse);

      expect(MaterialBand.i100.contains(0.899), isTrue);
      expect(MaterialBand.i100.contains(0.0), isTrue);

      // 覆盖性:任意覆盖率至少落在一个非"不限"档里
      for (final r in [0.0, 0.5, 0.899, 0.90, 0.95, 0.98, 0.999, 1.0]) {
        final hits = [
          for (final b in [MaterialBand.i1, MaterialBand.i10, MaterialBand.i100])
            if (b.contains(r)) b,
        ];
        expect(hits.length, 1, reason: '覆盖率 $r 应恰好命中一档,实际 $hits');
      }
    });

    test('of() 按覆盖率判档(与 contains 一致)', () {
      expect(MaterialBand.of(0.99), MaterialBand.i1);
      expect(MaterialBand.of(0.98), MaterialBand.i1);
      expect(MaterialBand.of(0.95), MaterialBand.i10);
      expect(MaterialBand.of(0.90), MaterialBand.i10);
      expect(MaterialBand.of(0.85), MaterialBand.i100);
    });

    test('fitLabel:符合 / 偏易 / 偏难;不限档不标注', () {
      expect(MaterialBand.i10.fitLabel(0.95), '符合 i+10');
      expect(MaterialBand.i10.fitLabel(0.99), '偏易');
      expect(MaterialBand.i10.fitLabel(0.80), '偏难');
      expect(MaterialBand.any.fitLabel(0.5), '');
    });

    test('每个非"不限"档都给 AI 一句难度说明(不能是空约束)', () {
      for (final b in [MaterialBand.i1, MaterialBand.i10, MaterialBand.i100]) {
        expect(b.hintForAi, isNotEmpty, reason: '${b.label} 缺 AI 提示');
        expect(b.hintForAi, contains(b.label));
      }
      expect(MaterialBand.any.hintForAi, isEmpty);
      expect(MaterialBand.any.isAny, isTrue);
    });

    test('parse:认名字,脏值一律回落"不限"(不抛)', () {
      expect(MaterialBand.parse('i10'), MaterialBand.i10);
      expect(MaterialBand.parse(null), MaterialBand.any);
      expect(MaterialBand.parse('乱码'), MaterialBand.any);
      expect(MaterialBand.parse(0.98), MaterialBand.any);
    });
  });

  group('MaterialPrefs(个性化找资源偏好)', () {
    test('空偏好:isEmpty / activeCount / summary 都按"没设置"表现', () {
      const p = MaterialPrefs.empty;
      expect(p.isEmpty, isTrue);
      expect(p.activeCount, 0);
      expect(p.summary, contains('还没设置偏好'));
      expect(p.hintForAi, isEmpty);
    });

    test('activeCount 按"生效项数"算:难度 + 每个类型 + 题材 + 补充需求', () {
      final p = MaterialPrefs.empty.copyWith(
        band: MaterialBand.i1,
        kinds: {'book', 'paper'},
        genres: '哲学',
        extra: '不要学术腔',
      );
      expect(p.activeCount, 5);
      expect(p.isEmpty, isFalse);
    });

    test('JSON 往返一致;脏类型被丢掉(不认识的 kind 不能污染源清单)', () {
      final p = MaterialPrefs(
        band: MaterialBand.i100,
        kinds: {'paper', '不存在的类型'},
        genres: '科技',
        extra: '短一点',
      );
      final back = MaterialPrefs.fromJson(p.toJson());
      expect(back.band, MaterialBand.i100);
      expect(back.kinds, {'paper'});
      expect(back.genres, '科技');
      expect(back.extra, '短一点');
      expect(back.toJson(), p.copyWith(kinds: {'paper'}).toJson());
    });

    test('坏 JSON / 非 Map 一律当空偏好(不能让材料中心打不开)', () {
      expect(MaterialPrefs.fromJson(null).isEmpty, isTrue);
      expect(MaterialPrefs.fromJson('这不是 Map').isEmpty, isTrue);
      expect(MaterialPrefs.fromJson({'band': 'x', 'kinds': 'book'}).isEmpty,
          isTrue);
    });

    test('preferredSources:选了类型 → 只留对应源;空 → 全部源', () {
      expect(MaterialPrefs.empty.preferredSources.length,
          MaterialSourceService.sources.length);

      final book = MaterialPrefs.empty.copyWith(kinds: {'book'});
      expect(book.preferredSources.map((s) => s.id), ['gutenberg']);

      final paper = MaterialPrefs.empty.copyWith(kinds: {'paper'});
      expect(paper.preferredSources.map((s) => s.id), ['arxiv']);

      // 偏好里的类型在源清单里找不到 → 回落全部(界面不能空白)
      final broken = MaterialPrefs.empty.copyWith(kinds: {'nonexistent'});
      expect(broken.preferredSources.length, MaterialSourceService.sources.length);
    });

    test('hintForAi 把四样偏好都带上,并含难度说明', () {
      final p = MaterialPrefs(
        band: MaterialBand.i1,
        kinds: {'book'},
        genres: '英式幽默',
        extra: '每篇 10 分钟内',
      );
      final hint = p.hintForAi;
      expect(hint, contains('公版书'));
      expect(hint, contains('英式幽默'));
      expect(hint, contains('每篇 10 分钟内'));
      expect(hint, contains('i+1'));
    });

    test('load():Hive 未打开时返回空偏好而不是抛异常', () {
      // 纯 Dart 测试里没有打开 Hive box —— 这条正是"进材料中心就崩"的防回归
      expect(() => MaterialPrefs.load(), returnsNormally);
      expect(MaterialPrefs.load().isEmpty, isTrue);
      expect(() => MaterialPrefs.lastQueryFor('书籍'), returnsNormally);
      expect(MaterialPrefs.lastQueryFor('书籍'), isEmpty);
    });
  });
}
