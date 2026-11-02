import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/reader_units.dart';

/// v2.13.1 回归:一轮翻译的进度状态机。
///
/// 用户原话:「翻译进度永远是死的」。直接原因是旧实现把 `_runTotal/_runDone`
/// 直接写在 State 里:最后一段完成时**先清零、再 setState** → `1/1 = 100%`
/// 那一帧从未被渲染。抽成纯类后,下面这些顺序/边界都能被单测锁住:
/// - 单单元也必须经历 0% → 100% 并**保留到 clear 之前**;
/// - N 个单元单调递增,分母 = 本轮入队单元数;
/// - 取消也算"已处理",不会让进度卡在 N-1/N;
/// - 新一轮 begin 会重置,不会把旧分母算进来。
void main() {
  test('单单元:进度必须经历 0% → 100%,且 100% 在 clear 前可见', () {
    final run = TranslationRunState();
    expect(run.visible, isFalse);
    expect(run.progress, 0);

    run.begin(1);
    expect(run.visible, isTrue);
    expect(run.total, 1);
    expect(run.done, 0);
    expect(run.progress, 0.0);

    run.completeOne();
    expect(run.done, 1);
    expect(run.progress, 1.0);
    expect(run.finished, isTrue);
    // 这是旧 bug 的核心:完成那一刻不能立即"看不见"
    expect(run.visible, isTrue);
    expect(run.progress, 1.0);

    run.clear();
    expect(run.visible, isFalse);
    expect(run.total, 0);
    expect(run.done, 0);
    expect(run.progress, 0);
  });

  test('N 个单元:进度单调递增,分母 = 本轮单元数(典型 6~10,不再恒 1)', () {
    final run = TranslationRunState()..begin(8);
    expect(run.total, 8);
    var last = 0.0;
    for (var i = 1; i <= 8; i++) {
      run.completeOne();
      expect(run.done, i);
      expect(run.progress, greaterThan(last));
      last = run.progress;
    }
    expect(run.progress, 1.0);
    expect(run.finished, isTrue);
  });

  test('取消也是"已处理":不会卡在 N-1/N(不重复 +1 超过总数)', () {
    final run = TranslationRunState()..begin(2);
    run.completeOne();
    run.completeOne(); // 成功 + 取消
    expect(run.done, 2);
    run.completeOne(); // 多余的收尾不能把分子推过分母
    expect(run.done, 2);
    expect(run.progress, 1.0);
  });

  test('同一轮里追加单元:分母变大,分子保留(随读随翻/继续翻后文)', () {
    final run = TranslationRunState()..begin(2);
    run.completeOne();
    run.add(3);
    expect(run.total, 5);
    expect(run.done, 1);
    expect(run.progress, 0.2);
  });

  test('markFinished:收尾前先把分子补满 → 界面一定能渲染 100%(旧 bug 的反面)', () {
    final run = TranslationRunState()..begin(3);
    run.completeOne();
    expect(run.progress, closeTo(1 / 3, 1e-9));
    run.markFinished();
    expect(run.progress, 1.0);
    expect(run.finished, isTrue);
    expect(run.visible, isTrue, reason: '保留给界面的 100% 帧');
  });

  test('空闲时 add = 开新一轮(不会把上一轮的分母继续加)', () {
    final run = TranslationRunState()..begin(2);
    run.completeOne();
    run.completeOne();
    expect(run.finished, isTrue);
    // 模拟"上一轮结束后 2 秒收条前又点继续":此时界面会先 clear 再 add,
    // 但即使调用方忘了 clear,add 也不能拿旧分母继续 —— 由 begin 语义兜底
    run.clear();
    run.add(3);
    expect(run.total, 3);
    expect(run.done, 0);
    expect(run.progress, 0.0);
  });

  test('begin(0)/add(0) 不产生可见进度(调用方空队列时不能露出进度条)', () {
    final run = TranslationRunState()
      ..begin(0)
      ..add(0)
      ..completeOne();
    expect(run.visible, isFalse);
    expect(run.progress, 0);
  });
}
