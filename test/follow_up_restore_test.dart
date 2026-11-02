import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/screens/input/widgets/follow_up_drawer.dart';

/// B0-1(2026-11-01 用户实测"追问抽屉收起再开又从头划")的纯函数回归。
///
/// 抽屉是 modal 路由,收起即销毁;每次打开的 `maxScrollExtent` 还可能不同
/// (DraggableScrollableSheet 能在 0.6↔0.85 之间拖)。所以"还原上次位置"
/// 必须按**比例**换算,不能直接按像素跳 —— 这组用例把边界钉死。
void main() {
  group('resolveFollowUpRestoreOffset — 追问抽屉位置还原', () {
    test('可滚区间没变 → 原样还原', () {
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 420,
          lastExtent: 1000,
          newExtent: 1000,
        ),
        closeTo(420, 0.001),
      );
    });

    test('抽屉被拖高(maxExtent 变大)→ 按比例放大', () {
      // 上次停在 40% 处(400/1000);这次可滚 1500 → 应落在 600
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 400,
          lastExtent: 1000,
          newExtent: 1500,
        ),
        closeTo(600, 0.001),
      );
    });

    test('抽屉被拖矮(maxExtent 变小)→ 按比例缩小', () {
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 800,
          lastExtent: 1000,
          newExtent: 500,
        ),
        closeTo(400, 0.001),
      );
    });

    test('上次内容不足一屏(lastExtent=0)→ 退回像素 clamp', () {
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 120,
          lastExtent: 0,
          newExtent: 300,
        ),
        closeTo(120, 0.001),
      );
      // 像素超出今天的可滚区间 → 夹到边界,而不是跳出一个非法值
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 999,
          lastExtent: 0,
          newExtent: 300,
        ),
        closeTo(300, 0.001),
      );
    });

    test('今天没有可滚空间(newExtent=0)→ 回到顶部', () {
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 420,
          lastExtent: 1000,
          newExtent: 0,
        ),
        0,
      );
    });

    test('脏值(负数/NaN/Infinity)→ 不抛异常且夹在合法区间', () {
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: -50,
          lastExtent: 1000,
          newExtent: 500,
        ),
        greaterThanOrEqualTo(0),
      );
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: double.nan,
          lastExtent: 1000,
          newExtent: 500,
        ),
        greaterThanOrEqualTo(0),
      );
      expect(
        resolveFollowUpRestoreOffset(
          lastOffset: 200,
          lastExtent: 1000,
          newExtent: 500,
        ),
        lessThanOrEqualTo(500),
      );
    });
  });
}
