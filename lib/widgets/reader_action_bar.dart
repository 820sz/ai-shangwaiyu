import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reader_paper.dart';
import 'reader_progress.dart';

/// 阅读器 C 方案(2026-11-06 用户拍板)的底部:贴底 2px 进度线 + 42px 把手区。
///
/// **零常驻按钮**是 C 方案的核心承诺之一:旧 `ReaderActionBar` 是一条单行
/// Row 里塞 6 个控件(模型 / 翻译 / 丰富形式 / 收词 / 追问 / 更多,见
/// `docs/READER-REDESIGN-OPTIONS-2026-11-06.md` §1.1),把屏高 22% 吃掉了还
/// 三套控件语言混用。现在底部只剩三样东西:
///
/// ```
/// ──────────── 2px 进度线(砖红)────────────
///  37% 已读          ── 36×4 抓手 ──          上滑工具
/// ```
///
/// 所有动作都收进「上滑阅读控制台」(见 `reader_console.dart`):
/// 上滑把手区 / 点任意处 / 点右侧 % 胶囊都能打开。
class ReaderBottomDock extends StatefulWidget {
  const ReaderBottomDock({
    super.key,
    required this.progress,
    required this.palette,
    required this.onOpenConsole,
    this.bottomInset = 0,
  });

  /// 阅读进度(0~1),只重建把手区里的数字与那条 2px 线
  final ValueListenable<double> progress;

  final ReaderPalette palette;

  /// 打开阅读控制台
  final VoidCallback onOpenConsole;

  /// 设备底部安全区(手势条/导航栏),由页面用 MediaQuery.viewPadding 传进来
  final double bottomInset;

  /// 把手区高度(C 规范 42px)
  static const double handleHeight = 42;

  /// 打开控制台所需的向上拖动距离
  static const double swipeThreshold = 16;

  @override
  State<ReaderBottomDock> createState() => _ReaderBottomDockState();
}

class _ReaderBottomDockState extends State<ReaderBottomDock> {
  double _dragDy = 0;

  void _open() => widget.onOpenConsole();

  void _onDragUpdate(DragUpdateDetails d) {
    _dragDy += d.delta.dy;
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // 慢拖过阈值、或者快速上滑(fling)都算"要上滑工具"
    if (_dragDy <= -ReaderBottomDock.swipeThreshold || velocity < -220) {
      _open();
    }
    _dragDy = 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Column(
      key: const ValueKey<String>('reader-bottom-dock'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 贴底 2px 进度线:常驻、不占布局、永远在视野里
        ReaderProgressLine(progress: widget.progress, palette: p),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: SizedBox(
            height: ReaderBottomDock.handleHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: <Widget>[
                  ValueListenableBuilder<double>(
                    valueListenable: widget.progress,
                    builder: (_, raw, _) => Text(
                      '${(raw.clamp(0.0, 1.0) * 100).round()}%',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已读',
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.2,
                      color: p.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  // 36×4 抓手:既是"能上滑"的暗示,也是真正的上滑热区
                  Container(
                    key: const ValueKey<String>('reader-bottom-handle'),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.inkFaint.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _open,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '上滑工具',
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        color: p.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 4 + widget.bottomInset),
      ],
    );
  }
}
