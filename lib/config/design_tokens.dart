import 'package:flutter/material.dart';

/// 设计令牌(v2.12 · 前端全面升级的地基)。
///
/// 历史:v2.5 建了第一版"唯一事实源"(间距/圆角/时长),v2.11 补了字阶与层级变体。
/// **但用户 2026-10-05 仍然觉得"整个软件毫无变化",10-23 给出最终原则**:
/// 「精简和高级、实用是第一位,在此基础上增加丰富性和趣味性」。
///
/// 这一版重写的依据(不是拍脑袋):
/// - 用户给的 5 张样图(扇贝阅读 / 训记 / 轻小说文库)里,**大卡圆角明显更大(20~24)、
///   卡片有柔和投影、标题字号对比更强**(详见 docs/FRONTEND-UPGRADE-PLAN.md);
/// - Apple 排印原则:字号阶梯越大,行高越紧、字距越负(tracking 随字号变化);
/// - 小字(元信息/标签)需要足够的字重与开放字距才可读。
///
/// 纪律:**只在这里加档位,页面里不许再写裸数值。**
class Gap {
  Gap._();

  /// 4:图标与文字之间
  static const double xxs = 4;

  /// 8:同一组内的元素
  static const double xs = 8;

  /// 12:组内小块
  static const double sm = 12;

  /// 16:卡片内边距
  static const double md = 16;

  /// 20:页面左右边距(比 16 更透气,阅读类 App 的标准做法)
  static const double page = 20;

  /// 24:两个区块之间
  static const double lg = 24;

  /// 32:大区块之间
  static const double xl = 32;

  /// 48:首屏大留白
  static const double xxl = 48;
}

class Radii {
  Radii._();

  /// 小控件(标签、输入框、小按钮)
  static const double control = 12;

  /// 卡片
  static const double card = 20;

  /// 大卡(内容 Hero 卡)
  static const double hero = 24;

  /// 底部弹层 / 大面板
  static const double sheet = 24;

  /// 胶囊(标签、主按钮)
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius heroRadius = BorderRadius.all(Radius.circular(hero));
  static const BorderRadius sheetRadius =
      BorderRadius.all(Radius.circular(sheet));
  static const BorderRadius controlRadius =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius pillRadius =
      BorderRadius.all(Radius.circular(pill));
}

class Motion {
  Motion._();

  /// 即时反馈(按下、打勾、开关)
  static const Duration tap = Duration(milliseconds: 120);

  /// 常规过渡(展开/收起、页面内切换)
  static const Duration transition = Duration(milliseconds: 240);

  /// 入场动画(页面进入、列表首屏)
  static const Duration enter = Duration(milliseconds: 420);

  /// 数字补间(统计/进度变化)
  static const Duration count = Duration(milliseconds: 600);

  /// 统一曲线:先快后慢,手感"跟手"(与 Apple 的标准出场曲线同族)
  static const Curve curve = Curves.easeOutCubic;

  /// 入场曲线:起步快、收尾柔和
  static const Curve enterCurve = Curves.easeOutQuart;

  /// 回弹(打勾、点赞这类"确认"动作)
  static const Curve pop = Curves.easeOutBack;
}

/// 字号阶梯(7 档)。
///
/// 为什么是 7 档而不是更多:档位越多越不统一(Refactoring UI 的原则)。
/// 用法按**语义**选,不是按像素凑:
/// - [display] 页面主标题(「每日精读」);
/// - [title] 大卡标题;
/// - [heading] 区块标题;
/// - [subhead] 卡片标题;
/// - [body] 正文;
/// - [meta] 元信息/日期/句数;
/// - [tag] 标签/徽标。
///
/// 行高与字距随字号成反比(大标题紧行高 + 负字距,小标签松字距),见各档注释。
class AppFont {
  AppFont._();

  static const double display = 28;
  static const double title = 22;
  static const double heading = 18;
  static const double subhead = 16;
  static const double body = 14.5;
  static const double meta = 12;
  static const double tag = 11;

  /// 旧调用点兼容(v2.11 起的名称)
  static const double micro = tag;

  /// 旧调用点兼容(v2.11 起的名称)
  static const double caption = meta;

  /// 页面主标题样式(紧行高 + 负字距 —— Apple 排印原则:字越大越要收紧)
  static const TextStyle displayStyle = TextStyle(
    fontSize: display,
    height: 1.15,
    letterSpacing: -0.5,
    fontWeight: FontWeight.w800,
  );

  /// 大卡标题
  static const TextStyle titleStyle = TextStyle(
    fontSize: title,
    height: 1.2,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w700,
  );

  /// 区块标题
  static const TextStyle headingStyle = TextStyle(
    fontSize: heading,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );

  /// 卡片标题
  static const TextStyle subheadStyle = TextStyle(
    fontSize: subhead,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// 正文
  static const TextStyle bodyStyle = TextStyle(
    fontSize: body,
    height: 1.45,
  );

  /// 元信息(数字 + 图标一组)
  static const TextStyle metaStyle = TextStyle(
    fontSize: meta,
    height: 1.3,
    letterSpacing: 0.1,
    fontWeight: FontWeight.w500,
  );

  /// 标签/徽标(小字要稍松字距才可读)
  static const TextStyle tagStyle = TextStyle(
    fontSize: tag,
    height: 1.2,
    letterSpacing: 0.3,
    fontWeight: FontWeight.w600,
  );
}

/// 层级(唯一两档)。保留 v2.11 的语义,数值交给主题。
class AppElevation {
  AppElevation._();

  static const double flat = 0;
  static const double raised = 3;
}

/// 面(背景)层级:同一张卡片按"浮起程度"取不同底色。
class AppSurface {
  AppSurface._();

  /// 主角卡(hero)的叠色强度
  static const int raisedTintAlpha = 16;

  /// 强调态的叠色强度(比 hero 弱)
  static const int accentTintAlpha = 10;
}

/// 阴影:**只两档**(浅色用)。
///
/// 为什么只有两档:阴影的作用是回答"这一层浮在页面上面多少",不是装饰。
/// 档位越多,层级越乱;而且深色下阴影几乎看不见(现有原则:深色靠亮度差),
/// 所以 [of] 在深色下**直接返回空** —— 由卡片的表面色差异承担层级。
///
/// 浅色值是"两段阴影"组合(近距离小阴影定边界 + 远距离大阴影给体积),
/// 这是做出"柔和而不脏"的常规做法。
class AppShadow {
  AppShadow._();

  static const List<BoxShadow> _sm = [
    BoxShadow(
      color: Color(0x0D1A1A2E),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x120F1115),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> _md = [
    BoxShadow(
      color: Color(0x141A1A2E),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x1A0F1115),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  /// 静置卡片
  static List<BoxShadow> sm(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const [] : _sm;

  /// 浮起(主角卡/弹层)
  static List<BoxShadow> md(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const [] : _md;
}

/// 页面级统一的边距(Padding)
class Insets {
  Insets._();

  /// 页面内容标准边距:左右 20、上 16(阅读类 App 给足呼吸感)
  static const EdgeInsets page = EdgeInsets.fromLTRB(20, 16, 20, 32);

  /// 卡片内部标准边距:16
  static const EdgeInsets card = EdgeInsets.all(16);

  /// 大卡内部边距
  static const EdgeInsets hero = EdgeInsets.all(20);

  /// 列表项内部
  static const EdgeInsets tile =
      EdgeInsets.symmetric(horizontal: 16, vertical: 12);
}
