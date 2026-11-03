# 新对话交接文档 · v4 视觉重做（创造模式专用）

> 写给**新会话**（创造模式）：这份文档是自包含的，读完即可继续，不需要翻旧对话。
> 生成时间：2026-11-03 19:45；项目：AI上外语 / ReadFlow；用户：xi283（中文）。
> 当前状态：**功能与数据层已闭环（最新发布 v2.23.0）；唯一下一步是前端视觉重做，
> 且用户要求新对话先探索几个不同的"视觉基调"给用户选，选定后再落地。**

---

## 0. 新对话开场速读（按顺序）

1. 本文档（`docs/HANDOFF-V4-CREATIVE.md`）——全部背景/状态/纪律/第一步；
2. `docs/V4-ART-DIRECTION.md`——美术方向（设计主张/三原则/视觉语言/炫技清单）；
3. `docs/V4-VISUAL-REDESIGN.md`——v4 方案（共享组件/四组屏/验收/交付流程）；
4. `docs/AUDIT-v3-2026-11-02.md`——用户提过的全部需求/问题逐条对照（看 §I 终版状态）；
5. `docs/ui-preview/`——已出的效果图（输入/输出/风格板）；
6. 桌面存档：`C:\Users\xi283\Desktop\AI上外语正式版项目\`（含 APK/源码快照/git bundle/全部文档）。

## 1. 用户与产品

- 用户：xi283，中文，上海。评判标准：**打开 App 第一眼的变化** + 内页是否同样讲究 + 装机可用。
- 产品：ReadFlow / AI上外语，Flutter App，英语学习闭环「输入（读）→ 输出（写词/写句/写段/写篇）→ 助理（诊断/任务/复盘）→ 数据（能力/备份/周报）」。
- 核心哲学（用户原话）：「真真正正让二语学习者一站式、踏踏实实提高外语水平」「背单词必须基于输入输出闭环与材料语境」「不割韭菜、不靠空话」。
- **听力明确不做**（用户 11/02 说"听力不用管"）。

## 2. 当前状态（2026-11-03）

| 项 | 状态 |
|---|---|
| 最新已发布 | **v2.23.0+83**，commit `7752be8`，GitHub `820sz/ai-shangwaiyu` release v2.23.0；桌面 `ReadFlow-v2.23.0.apk`；sha256 `cba797a5…ff85` |
| 数据库 | dbVersion **22**，只能前向 |
| 质量基线 | analyze 0 error/0 warning（8 条存量 info）；全量 **1577 passed + 1 skip + 1 已知假失败**（`profile_card_test` Hive 假时钟） |
| 当前代码 | `pubspec.yaml = 2.24.0+84`，**未提交、未发布**（v4 迁移中） |
| 本地/远端 | master == origin/master == `7752be8`（v4 改动只在工作区） |
| 存档 | `C:\Users\xi283\Desktop\AI上外语正式版项目\`（README/需求清单/进度/v4 方案/架构/复盘/产物） |

### 功能已闭环（不用再补）：
输入（材料中心/书架/分类/AI 找材料/公开源/拍照/链接/阅读器含翻译目录）、
输出（四阶练习+语境填空+写句三题型+题库+rubric 评分+折算档位+真题抓取）、
助理（五维现状/任务状态机/4 条诊断/复盘指标/周报）、
数据（备份 v2 十表/能力快照全链路/死字段回写/语法分项/错误档案）。

### v4 已完成的代码（工作区未提交）
- `lib/widgets/v4/v4_kit.dart`：v4 共享组件（页面骨架 `V4PageScaffold`、渐变头图 `V4HeroHeader`、
  阶段卡 `V4StageCard`、动作砖 `V4ActionTile`、题材 tabs `V4TopicTabs`、统计块 `V4StatBlock`、
  列表卡 `V4ListCard`、区块标题 `V4SectionTitle`、胶囊按钮 `V4PillButton`、进度环 `V4ProgressRing`、
  三态 `V4Skeleton/V4Empty/V4Error`、微噪点 `V4Grain`）。
- `lib/screens/input/input_home.dart`：已迁移 v4 骨架（渐变头图+材料中心按钮+题材 tabs+动作砖+区块标题）。
- `lib/screens/output/output_home.dart`：标题区已换 v4（眉标+大标题+tonal 按钮）。
- `lib/screens/output/practice_setup_screen.dart`：顶部阶位引导卡 + 材料卡收敛。
- `lib/widgets/material_cover.dart`：小封面改单字标（不再出现「随着疫」这种截断字）。
- `test/ui_v4_preview_test.dart`：渲图管道（输入/输出/风格板，明暗两套 PNG → `build/ui_v4_preview/`）。
- `docs/ui-preview/`：已出图（`v4-input-light.png`、`v4-output-light.png`、`v4-style-board.png` + 深色）。

## 3. 用户最新要求（2026-11-03）

1. 前端要**高级、精美、不喧宾夺主、有逼格**；可以炫技（不抢内容的前端技术），
   在保证内容呈现舒服的前提下**不失丰富性**；
2. **内页也要有同样水准**，不能只改主屏（原话："不要只在大界面表面做，点进每一个功能又是一坨屎"）；
3. 交付方式：**先渲图给用户看，用户选/确认后再打包**（原话："别让我装盲盒"）；
4. 新对话**先探索几个方案基调**（视觉方向），用户选一个，再继续落地整个 App；
5. 创造模式已开，新对话有更长/更自由的实现空间——但产出标准不变。

## 4. 新对话第一步（必须先做这个，不要直接开工改屏）

### 4.1 探索 3~5 个"视觉基调"方案

在创造模式里，先做**同一批屏的多种视觉风格**，渲染成 PNG 对比，让用户选基调。
建议方向（可增可减，但至少 3 个、最多 5 个）：

| 代号 | 基调 | 关键词 | 视觉特征 |
|---|---|---|---|
| A | 杂志编辑风（当前 v4 起点） | 纸感、域色、大标题 | 暖中性底、渐变头图+噪点、域色描边卡、大字号 |
| B | 深色专业风（夜读） | 深底、低饱和、发光线 | 近黑底、域色降低饱和度、细发光描边、图表亮色 |
| C | 明亮果冻风（iOS 健康类） | 大圆角、彩色渐变卡、毛玻璃 | 白底、彩色渐变卡片、玻璃浮层、圆润图标 |
| D | 极简工具风（Linear/Notion） | 冷灰、细线、等宽数字 | 冷灰白、1px 细线、无阴影、等宽数字、单一强调色 |
| E | 复古印刷风（报刊/文学） | 米色纸、衬线、砖红/墨绿 | 米白纸底、英文衬线标题、砖红强调、版式分栏 |

### 4.2 每个方案渲染什么

同一批「样张」→ PNG（浅色即可，至少 A/B/C 各一套；如时间允许加深色）：
1. 输入首页（头图 + 题材 tabs + 继续读海报 + 动作砖 + 列表卡）；
2. 输出首页（四阶阶段卡 + 数据块）；
3. 材料卡片 + 阶段卡 + 按钮/标签 + 空态（风格板）。

### 4.3 交互方式

- 每方案 1~3 张 PNG；用 `present` 工具给用户文件卡（**必须用 present，别用内联绝对路径**，
  用户之前说"渲染图看不到"）；
- 附一句话说明每方案的气质与取舍；
- **用户选定基调后，再按四组开始落地**；不要一次就把四组全改了。

## 5. 选定基调后的落地计划（四组）

| 组 | 范围 |
|---|---|
| 1 | 输入链路：输入首页、材料中心、题材分类页、书架、收藏、阅读器（正文/翻译/目录/字号/查词/追问）、拍照相册导入、链接导入、识图结果、材料分组、词汇本列表/词卡/复习 |
| 2 | 输出链路：输出首页五阶卡、四阶设置页、答题页、批改结果（rubric+折算档）、写译工作台、题库、练习中心、真题抓取、旧计划页 |
| 3 | 助理链路：助理首页（趋势+结论）、现状、任务列表/详情/编辑、复盘、聊天、水平测试 |
| 4 | 我的链路：我的、统计、周报、学习偏好、API 设置、错误档案、写译记录、备份与恢复、关于/更新 |

每屏：改代码 → `dart analyze <文件>` → 相关测试 → 渲图（真实页面优先，整页渲不了就用同构样张）→ 给用户看 → 确认后继续。
四组全过 → 全量 `flutter analyze` + `flutter test` → 打 **v2.25.0** APK → 桌面 `ReadFlow-v2.25.0.apk` + GitHub Release。

## 6. 设计标准（用户验收口径）

1. 第一眼与旧版明显不同：有色彩/头图/统一卡片语言，不是"白底+大黑字+蓝按钮"；
2. 材料中心等主功能**首屏可见**（旧版入口藏在"换一份"文字键里，被骂过）；
3. 内页与主屏同一视觉语言，不得点进去变成旧白卡；
4. 每屏有加载/空/错误态且风格统一；
5. 色彩克制：头图渐变只在页顶、正文区中性、主行动唯一、强调色 ≤2；
6. 动效只在层级/状态变化，尊重系统"减少动态"；
7. 封面上不出现截断标题（小封面用单字标/图形，标题在卡外）；
8. 深色模式成立、对比度达标；
9. 不编造数据（真实数字/真实依据）。

## 7. 教训（务必避免重复）

1. **别把"功能清单完成/测试全绿"当成交差**——用户看的是第一眼和手感；
2. **别只改主屏**——内页不重做等于没做（用户原话"点进每一个功能又是一坨屎"）；
3. **别盲盒打包**——先渲图，用户确认；用户明确拒绝"装一版毫无区别的包"；
4. **别把入口藏起来**——材料中心事件是事故，主功能必须一眼可见；
5. **别用截断标题当封面**——小尺寸封面用单字标/图形；
6. **别一次并发太多主线**——v4 期间冻结功能/数据层，只做视觉；
7. **别用大量文字解释代替可视产出**——出图 > 描述。

## 8. 技术指南

### 渲图管道（关键）
- 文件：`test/ui_v4_preview_test.dart`；输出：`build/ui_v4_preview/*.png`；
- 已处理：中文字体（NotoSansSC/Deng/simhei 候选，注册为 `PreviewCJK` + `Roboto`）、
  MaterialIcons（从 Flutter SDK cache 加载）、RepaintBoundary → PNG；
- 新增预览：在文件末尾加 `_StyleBoard` 类似的 widget，然后加一个 `testWidgets` 调用 `_export`；
- **不要**把真实整页（涉及 Hive/DB/无限动画）塞进 widget test：会卡 `pumpAndSettle`；
  预览用纯组件/同构样张，或显式 `pump(Duration)` 若干帧；
- 给用户看图时用 `present`（file card），**不要**只写内联绝对路径（用户看不到）。

### 环境与命令（仓库 `D:\readflow`）
```powershell
$env:FLUTTER_ALREADY_LOCKED='true'
flutter analyze --no-fatal-infos     # 基线 0 error/0 warning（8 条存量 info）
flutter test --no-pub                 # 1577 passed + 1 skip + 1 已知假失败
flutter build apk --release --target-platform android-arm64
# 发版：commit → RF_DIFF_BASE=<远端sha> → tool\push_via_api.ps1 → gh release create → 同步 master
```
发布说明格式：必须含 `## 更新内容` + 编号列表 `1. 2. 3.`（App 内更新页解析依赖）。

### 约束与已知坑
- 只改源码用 read/write/edit；`PowerShell Get-Content|Set-Content` 会改坏 pubspec 编码；
- 子代理任务并行时写范围要不相交；v4 期间不建议再开子代理（上次三个子代理中途失败，浪费时间）；
- `profile_card_test` 假失败与 App 无关，别去修；
- 已有设计令牌：`lib/config/design_tokens.dart`（Gap/Radii/AppFont/AppShadow/Motion）；
- 已有旧组件：`app_ui.dart`、`design_kit.dart`、`widgets/graphics/`（13 域图形/封面/空态/图表）；
- dbVersion 22，备份格式 v2，不要动数据库结构。

## 9. 可直接粘贴给新会话的开场 prompt

```
你是 ReadFlow（AI上外语）的前端主导，代码仓库 D:\readflow。这是一个 Flutter 英语学习 App。
当前：功能与数据层已闭环并发布到 v2.23.0（commit 7752be8）；工作区有未提交的 v4 视觉重做进度
（lib/widgets/v4/v4_kit.dart、input_home 已迁移、渲图管道 test/ui_v4_preview_test.dart）。
用户 xi283 的要求：前端必须"高级、精美、不喧宾夺主、有逼格"；内页与主屏同样水准；
先渲图给用户看，用户确认后再打包；听力不做。

第一步（现在只做这个）：读 docs/HANDOFF-V4-CREATIVE.md、docs/V4-ART-DIRECTION.md、
docs/V4-VISUAL-REDESIGN.md，然后在现有 v4 组件基础上探索 3~5 个"视觉基调"方案
（杂志编辑风/深色专业风/明亮果冻风/极简工具风/复古印刷风…），
用 test/ui_v4_preview_test.dart 的渲图管道为每个方案渲 1~3 张 PNG
（输入首页、输出首页、风格板），用 present 工具发给用户，
让用户选定基调。用户选定前不要开始逐屏落地，不要打包 APK。
```

## 10. 关键文件索引

- 视觉系统：`lib/widgets/v4/v4_kit.dart`、`lib/config/design_tokens.dart`、`lib/widgets/graphics/`
- 渲图：`test/ui_v4_preview_test.dart`、`docs/ui-preview/`
- 输入：`lib/screens/input/input_home.dart`（已迁移）、`material_center_screen.dart`、`material_reader_screen.dart`
- 输出：`lib/screens/output/output_home.dart`（部分迁移）、`practice_setup_screen.dart`（部分迁移）
- 助理：`lib/screens/tutor/tutor_home.dart`
- 我的：`lib/screens/profile/`
- 文档：`docs/HANDOFF-V4-CREATIVE.md`（本文）、`docs/V4-ART-DIRECTION.md`、`docs/V4-VISUAL-REDESIGN.md`、`docs/AUDIT-v3-2026-11-02.md`、`docs/TASK-BOARD-V3.md`
- 存档：`C:\Users\xi283\Desktop\AI上外语正式版项目\`（APK/源码快照/git bundle/预览图/全部文档）
