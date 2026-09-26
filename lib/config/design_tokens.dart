import 'package:flutter/material.dart';

/// 设计令牌(v2.5,U1:前端大升级的地基)。
///
/// 之前每个页面各写各的间距/圆角/时长:同样"卡片间距"能出现 6、8、10、12、16 五种值,
/// 几十个页面叠起来就是用户说的"排版乱、臃肿"。这里把**唯一的事实源**定下来:
/// 新代码只能用这些常量,老代码逐屏替换。
///
/// 尺度的取法(不是拍脑袋):
/// - 间距 4 的倍数(4/8/12/16/24/32)—— 与 Material 的 8pt 网格一致,
///   奇数间距在不同 DPI 上会产生半像素错位;
/// - 圆角只用 3 档:小控件 10、卡片 16、弹层 20 ——
///   圆角档位越多越显得"不是一套设计";
/// - 动效时长只用 3 档:120(反馈)/ 220(过渡)/ 420(入场)——
///   同一层级用同一个时长,手感才一致。
class Gap {
  Gap._();

  /// 4:图标与文字之间
  static const double xxs = 4;

  /// 8:同一组内的元素
  static const double xs = 8;

  /// 12:组内小块
  static const double sm = 12;

  /// 16:页面左右边距 / 卡片内边距
  static const double md = 16;

  /// 24:两个区块之间
  static const double lg = 24;

  /// 32:页面底部留白
  static const double xl = 32;
}

class Radii {
  Radii._();

  /// 小控件(标签、输入框、小按钮)
  static const double control = 10;

  /// 卡片
  static const double card = 16;

  /// 底部弹层 / 大面板
  static const double sheet = 20;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius controlRadius =
      BorderRadius.all(Radius.circular(control));
}

class Motion {
  Motion._();

  /// 即时反馈(按下、打勾、开关)
  static const Duration tap = Duration(milliseconds: 120);

  /// 常规过渡(展开/收起、页面内切换)
  static const Duration transition = Duration(milliseconds: 220);

  /// 入场动画(页面进入、列表首屏)
  static const Duration enter = Duration(milliseconds: 420);

  /// 统一曲线:先快后慢,手感"跟手"
  static const Curve curve = Curves.easeOutCubic;

  /// 回弹(打勾、点赞这类"确认"动作)
  static const Curve pop = Curves.easeOutBack;
}

/// 页面级统一的边距(Padding)
class Insets {
  Insets._();

  /// 页面内容标准边距:左右 16、上 12
  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 12, 16, 24);

  /// 卡片内部标准边距:14(比 16 略紧,视觉上更"整")
  static const EdgeInsets card = EdgeInsets.all(14);

  /// 列表项内部
  static const EdgeInsets tile = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
}
