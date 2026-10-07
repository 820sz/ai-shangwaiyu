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

/// 字号阶梯(v2.11 补)。
///
/// 为什么必须补:在此之前全库的字号是**手写散落的** —— `fontSize: 11 / 11.5 / 12 /
/// 12.5 / 14.5 / 15 / 17` 在 152 个文件里各写各的(体检查出来的),于是同一个层级的
/// 文字在不同页面不一样大,页面之间没有"节奏"。用户 10/5 的原话是"前端非常单一…
/// 各种各样的前端表现都非常单调平庸" —— **缺少字号对比**就是其中一半原因。
///
/// 这套阶梯只 **5 档**,刻意不细化:档位越多越不统一。用法是"按语义选档",
/// 不是"按像素凑数":标题用 title、正文用 body、辅助信息用 caption 或 micro。
class AppFont {
  AppFont._();

  /// 超小:角标、封面上的种类小字(卡片里的"第三层信息")
  static const double micro = 10.5;

  /// 小:辅助说明、meta 行
  static const double caption = 12;

  /// 正文:列表项标题、表单内容
  static const double body = 14;

  /// 小标题:区块内的小标题
  static const double title = 15.5;

  /// 区块/页面级大标题
  static const double heading = 19;
}

/// 层级(唯一两档)。
///
/// 为什么只有两档:M3 的 `elevation` 在深色主题下几乎看不见(theme.dart 的注释
/// 已经写过这点),堆 3、6、12 只会变成噪点。这里只区分"平铺"与"浮起":
/// - [flat] = 0:列表里的常规卡片(靠 outline 描边区分,不靠阴影);
/// - [raised] = 3:需要抢视线的主角卡(今日精读、当前任务)。
/// 深色下它主要靠**背景色差异**体现(见 [AppSurface.raisedTintAlpha])。
class AppElevation {
  AppElevation._();

  static const double flat = 0;
  static const double raised = 3;
}

/// 面(背景)层级:同一张卡片按"浮起程度"取不同底色。
///
/// 深浅色两套都只是**在 surface 上叠一点点 onSurface / primary 的透明度** ——
/// 不用硬编码色值,才能跟着主题走(亮暗两套都成立)。
class AppSurface {
  AppSurface._();

  /// 主角卡(hero)的叠色强度(浅色下靠 primary 提亮,深色下靠 onSurface 提亮)
  static const int raisedTintAlpha = 16;

  /// 强调态的叠色强度(比 hero 弱,用于"当前选中/进行中")
  static const int accentTintAlpha = 10;
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
