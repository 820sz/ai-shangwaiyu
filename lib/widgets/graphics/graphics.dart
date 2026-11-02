/// ═══════════════════════════════════════════════════════════════════════
/// 图形资产系统(v2.13 · 批 1)—— 统一出口。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 用户原话:"你没有生图,但是有建模、代码的能力,所以看看哪些地方可以加入
/// 一些视觉性元素"。这个目录就是答案:**全 App 的分类/封面/空态/数据图形
/// 全部用代码画,零图片资源、零 pub 依赖、明暗两套主题自适应**。
///
/// 为什么只暴露一个 import 入口:
/// 界面文件只要 `import '../widgets/graphics/graphics.dart';` 就能拿到全部资产,
/// 不用记文件名;将来加一套图形("写作/听力"之类)也不会引起界面层 import 大改。
///
/// 资产清单:
/// - [DomainGraphic]      13 个领域身份图形(科技/商业/健康/文化/旅行/语言/备考/
///                        学术/新闻/书/音频/笔记/兜底)
/// - [MaterialCoverArt]   7 种材料封面身份背景(3:4 竖版 / 16:9 横版)
/// - [EmptyArt]           5 种空态插图(漂浮书页/纸飞机/散落字母/放大镜/波纹)
/// - [SparkBars]/[TrendLine]/[HeatmapCalendar]/[RadialGauge]  4 个数据图形
/// - [OutputTierGraphic]  输出四阶(单词→句子→段落→作文)
/// - [GraphicFrame]       统一外壳(尺寸/圆角/面板/RepaintBoundary/无障碍)
/// - [GraphicsPalette]    颜色/尺寸/笔触的唯一事实源(给需要自绘的新资产用)
///
/// 画风纪律(新增资产也必须遵守):
/// 线条 2.4~4.0(按尺寸)、圆角统一、最多两种色相、不加阴影、不用艳渐变。
library;

export 'data_graphics.dart';
export 'domain_graphics.dart';
export 'empty_art.dart';
export 'graphics_core.dart';
export 'graphics_palette.dart';
export 'material_cover_art.dart';
