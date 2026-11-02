import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/utils/material_group.dart';

/// A6 回归:手动归类后词必须**真的离开「未归类」**。
///
/// 用户实测:在生词本里把词归到「书籍」,回到「我的学习材料」它还挂在「未归类」。
/// 根因有两个,都在这里锁住:
/// 1. 取消子分类对话框时旧实现**照样移动** → 分类改了、material_path 没改
///    (这条在 vocab_list._batchMove 里修,已改为"取消 = 整件事取消");
/// 2. 材料名留空时旧实现拼出只有一级的伪路径 `书籍` → 分组认不出是哪本书。
void main() {
  Vocabulary voc(String word, {String? path, String? page, String? book}) =>
      Vocabulary(
        word: word,
        materialPath: path,
        sourcePage: page,
        sourceBook: book,
      );

  group('buildMaterialPath:一律两级,空名字落「未命名材料」', () {
    test('正常名字', () {
      expect(buildMaterialPath(category: '书籍', name: '三体'), '书籍/三体');
      expect(buildMaterialPath(category: '外刊', name: 'The Economist'),
          '外刊/The Economist');
    });

    test('名字为空 / 只有空白 → 明确的「未命名材料」分组(不是裸分类名)', () {
      expect(buildMaterialPath(category: '书籍', name: ''), '书籍/未命名材料');
      expect(buildMaterialPath(category: '书籍', name: '   '), '书籍/未命名材料');
    });

    test('首尾空白被清掉(手打名字常带空格)', () {
      expect(buildMaterialPath(category: '书籍', name: '  三体  '), '书籍/三体');
    });
  });

  group('groupMaterials:有路径才进得了对应分组', () {
    test('移动后(带两级路径)不再出现在「未归类」', () {
      final groups = groupMaterials([
        voc('apple', path: '书籍/三体', page: 'p12'),
      ], category: '书籍');
      final labels = groups.map((g) => g.label).toList();
      expect(labels, contains('三体'));
      expect(labels, isNot(contains('未归类')));
    });

    test('路径为空 → 才归到「未归类」(这是正常兜底,不是 bug)', () {
      final groups = groupMaterials([
        voc('apple'),
      ], category: '书籍');
      expect(groups.map((g) => g.label), contains('未归类'));
    });

    test('空名字落到「未命名材料」分组,而不是裸「书籍」', () {
      final path = buildMaterialPath(category: '书籍', name: '');
      final groups = groupMaterials([
        voc('apple', path: path),
      ], category: '书籍');
      expect(groups.map((g) => g.label), contains('未命名材料'));
    });
  });

  /// v2.13.1 回归(用户 2026-11-01 截图):移动弹层同时出现「书籍/《Character》」
  /// 与「书籍/书籍/《Character》」—— 移动链路把完整路径当材料名二次拼前缀。
  /// 归一后同一本书只能有一个分组键,否则永远不会并入老分类。
  group('normalizeMaterialPath:折掉重复的前导分类段', () {
    test('一次二次拼接 → 折回干净路径', () {
      expect(normalizeMaterialPath('书籍', '书籍/书籍/《Character》'),
          '书籍/《Character》');
    });

    test('多次拼接(三层以上)也一次折干净', () {
      expect(normalizeMaterialPath('书籍', '书籍/书籍/书籍/《Character》'),
          '书籍/《Character》');
      expect(normalizeMaterialPath('书籍', '书籍/书籍/书籍/书籍/《Character》'),
          '书籍/《Character》');
    });

    test('干净路径幂等(调用方可以无脑先归一)', () {
      expect(normalizeMaterialPath('书籍', '书籍/《Character》'),
          '书籍/《Character》');
      expect(normalizeMaterialPath('教材', '教材/新概念英语/第2册'),
          '教材/新概念英语/第2册');
    });

    test('两段的「书籍/书籍」是合法材料名(叫「书籍」),不能被折成裸分类', () {
      expect(normalizeMaterialPath('书籍', '书籍/书籍'), '书籍/书籍');
    });

    test('空段/首尾空白被清掉(历史脏值)', () {
      expect(normalizeMaterialPath('书籍', ' 书籍 / 书籍 / 《Character》 '),
          '书籍/《Character》');
      expect(normalizeMaterialPath('书籍', '书籍//《Character》'),
          '书籍/《Character》');
    });

    test('缺分类前缀时补上分类;只有分类名时落「未命名材料」', () {
      expect(normalizeMaterialPath('书籍', '《Character》'),
          '书籍/《Character》');
      expect(normalizeMaterialPath('书籍', '书籍'), '书籍/未命名材料');
      expect(normalizeMaterialPath('书籍', '   '), '');
    });

    test('跨分类/无分类前缀的脏值不会把分类改掉', () {
      expect(normalizeMaterialPath('书籍', '《三体》/第一部'),
          '书籍/《三体》/第一部');
    });

    test('normalizeGroupName:自由文本只折重复前导段(无分类前缀)', () {
      expect(normalizeGroupName('书籍/书籍/《Character》'), '书籍/《Character》');
      expect(normalizeGroupName('新视野教材'), '新视野教材');
      expect(normalizeGroupName(' 论文 / 2026 '), '论文/2026');
    });
  });

  group('归一后分组:同一本书只出现一个 MaterialGroup', () {
    test('脏路径 + 干净路径的同一批词,归一后只剩一个分组', () {
      final items = [
        voc('apple', path: '书籍/《Character》', page: 'p3'),
        voc('banana', path: '书籍/书籍/《Character》', page: 'p3'),
      ].map((v) {
        final fixed = normalizeMaterialPath('书籍', v.materialPath!);
        return v.copyWith(materialPath: fixed);
      }).toList();
      final groups = groupMaterials(items, category: '书籍');
      expect(groups.length, 1);
      expect(groups.single.path, '书籍/《Character》');
      expect(groups.single.label, '《Character》');
      expect(groups.single.totalCount, 2);
    });
  });
}
