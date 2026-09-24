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
}
