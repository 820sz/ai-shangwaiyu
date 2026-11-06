# 助理 / 我的 两板块前端升级 · 方案与真实渲染预览

> 日期：2026-11-06 · 范围：`lib/screens/tutor/`（助理）+ `lib/screens/profile/`（我的）
> 用户要求：这两个板块要**和输入板块同水准**，「不要只在大界面表面做，点进每一个功能又是一坨屎」。
> 本轮只交**方案 + 真实渲染预览**：**不改 lib/ 生产代码、不 commit、不改 pubspec、不装依赖**。选型确认后再进入实现。
>
> 预览图（真实渲染，pixelRatio 3，390×844 逻辑尺寸）：
> `docs/ui-preview/real/assistant-A.png`、`assistant-B.png`、`assistant-C.png`
> `mine-A.png`、`mine-B.png`、`mine-C.png`
> `detail-A.png`、`detail-B.png`、`detail-C.png`

---

## 0. 一页结论

**现状判定：不是「没做视觉」，是「只做了首页头图」。**

助理和我的两个 Tab 首页已经是 v4 果冻头（`tutor_home.dart:242`、`profile_home.dart:98`），
但两个板块共 **12 个内页仍挂着裸 `AppBar`**。而 v4 内页组件不仅早就写好，**输入板块已经用了 12 处**
（`V4JellyAppBar` `v4_kit.dart:495`：`material_channel_screen.dart:1462`、`material_library_screen.dart:295`、
`reading_quiz_screen.dart:125/187`、`process_chat.dart:1297` 等；`V4DetailHeader` `v4_kit.dart:317` 还有 4 处），
**助理板块 0 处、我的板块 0 处 `V4JellyAppBar`**（我的只有书签/词卡/生词本 3 屏用了 `V4DetailHeader`：
`bookmarks_screen.dart:57`、`vocab_detail.dart:44`、`vocab_list.dart:196`）。
也就是说：**同一个 App 里，输入链已经换成新骨架，助理/我的链还停在旧骨架**——
这比「整体旧版」更刺眼，也说明这不是能力问题，是这两条链没跟上。

三个方向（同一批内容，只换设计语言，便于一眼比较）：

| | 方向 | 一句话主张 | 适合谁 |
|---|---|---|---|
| **A** | 诊断台 | 助理是我的私人教练仪表盘：一屏看完全部指标，数字优先，行动只有一处 | 想「一眼知道我现在几斤几两」 |
| **B** | 每日简报 | 每天早上一张纸：今天做什么、昨天怎么样、一句提醒；像人写的，不像系统报的 | 想「每天有个理由打开它」 |
| **C** | 极简档案 | 只有字、线、数字和一个颜色；去掉所有卡片与渐变，像一本可检索的档案 | 想「冷静、耐看、不吵」 |

**推荐：B 作两个板块的主语言 + A 作「数据内页」的排版（统计 / 错误档案 / 复盘）。**
理由见 §3.1：两个板块是**低频页**，真正的问题不是「不好看」而是「没有打开的理由」；
B 用「每日简报 / 本周报告」给理由，A 用密度承接「来查数据」的内页，两者共用一套 tokens，
总成本比单独做两套低。C 不推荐进主流程（与用户之前骂过的「白底黑字蓝按钮」撞脸风险最高）。

成本（选型后）：**B ≈ 3–4 天 / 1200 行，A ≈ 2–3 天 / 900–1200 行，两者合并 ≈ 5 天**。

---

## 1. 现状审计（file:line）

### 1.1 跨屏共性问题（这是「点进去又是一坨屎」的真正来源）

| # | 问题 | 证据（file:line） | 后果 |
|---|---|---|---|
| P1 | **12 个内页仍是裸 `AppBar`**，首页却是 `V4HeroHeader` | `stats_page.dart:55`、`weekly_report_screen.dart:263`、`error_archive_screen.dart:186`、`api_settings.dart:542`、`appearance_screen.dart:31`、`backup_screen.dart:264`、`bookmarks_screen.dart:488`、`widget_settings_screen.dart:85`、`placement_test_screen.dart:310`、`tutor_chat_screen.dart:467`、`tutor_interview_screen.dart:257`、`writing_logs_screen.dart:76` | 首页→内页发生「换 App」的断裂；用户说「表面做了、点进去没做」的实锤 |
| P2 | **输入链已迁移、助理/我的链没迁移** | 输入板块 `V4JellyAppBar` **12 处**（`material_channel_screen.dart:1462`、`material_library_screen.dart:295`、`reading_quiz_screen.dart:125/187`、`process_chat.dart:1297`、`material_discover_screen.dart:248`、`material_browse_screen.dart:131`、`category_material_screen.dart:378`、`ai_material_search.dart:301`、`learner_preferences_screen.dart:222`、`learner_profile_screen.dart:65`、`material_recommendation_detail_screen.dart:317`）+ `V4DetailHeader` 4 处；**助理 0 处 / 我的 0 处 `V4JellyAppBar`**（我的仅 3 屏用 DetailHeader：`bookmarks_screen.dart:57`、`vocab_detail.dart:44`、`vocab_list.dart:196`） | 不是缺组件，是**两条链没跟上**——属于最低成本、最高感知的一刀 |
| P3 | **页面边距三套并存** | 20：`tutor_home.dart:306`、`profile_home.dart:118`、`stats_page.dart:104`、`placement_test_screen.dart:393`；16：`writing_logs_screen.dart:119`、`error_archive_screen.dart:197`；12：`weekly_report_screen.dart:292` | 两屏并排看，标题左边对不齐——用户说的「不够统一」 |
| P4 | **两个字阶系统并存** | 新：`AppFont.metaStyle`（`stats_page.dart:174`、`:228`、`:281`）；旧：`theme.textTheme.bodySmall/labelSmall` 裸用（`weekly_report_screen.dart:346,404,412,463,483,554,565,628,650,794` 共 11 处） | 同一 App 里「元信息」两种大小/字重，跨屏跳字 |
| P5 | **卡片语言三套** | `AppCard`（`app_ui`，radius 20）／`V4*` 卡（radius 26）／`weekly_report` 自建 `_Section`（`weekly_report_screen.dart:728-800`，内部 `borderRadius: 8` `:781`、`ClipRRect radius 3` `:633`） | 圆角从 3 到 26 全有，视觉上「东一块西一块」 |
| P6 | **旧 Material 控件残留**（按文件统计 `Card/ListTile/ExpansionTile/AlertDialog/showModalBottomSheet/ChoiceChip/SwitchListTile` 命中数） | `tutor_home.dart` **27**、`api_settings.dart` 10、`backup_screen.dart` 10、`stats_page.dart` 9、`placement_test_screen.dart` 8、`error_archive_screen.dart` 7、`appearance_screen.dart` 6、`widget_settings_screen.dart` 6、`profile_home.dart` 5、`tutor_chat_screen.dart` 4 | 助理首页 27 处是最重的；任务操作还是底部 `ListTile` 菜单（`tutor_home.dart:1071,1078,1084,1090,1096`） |
| P7 | **助理没有「任务详情页」** | 任务详情 = `showModalBottomSheet`（`tutor_home.dart:1044-1123`）；复盘 = 页内一张卡（`tutor_home.dart:431-436`） | 用户说的「点进每一个功能」在助理侧根本无页可点——详情/复盘必须新开页面 |
| P8 | **我的首页没有「下一步」** | 9 个 `AppActionTile` 平铺（`profile_home.dart:134-320`），「学习统计 / 本周报告 / 错误档案 / 备份」与「API 设置 / 外观 / 小组件」视觉权重完全相同 | 数据入口与配置入口同级，用户找不到「现在该看什么」 |
| P9 | **写译记录没进「我的」** | `writing_logs_screen.dart` 在 `lib/screens/writing/`，入口只在输出板块（`output_home.dart:18,531`）；`profile_home.dart:174-223` 的「数据与回顾」只有统计/周报/错误/备份 | 任务清单里的「写译记录」在「我的」里查无此入口 |
| P10 | **空态不统一** | `AppEmpty`（`profile_home.dart:239`）／`EmptyState`（`weekly_report_screen.dart:360`）／`ChartEmptyHint`（`weekly_report_screen.dart:386`）／裸 `Text` + `FilledButton` 重试（`tutor_home.dart:288-301`、`placement_test_screen.dart:350-373`） | 「没有数据」四种长相，用户每屏都要重新认一次 |

### 1.2 逐屏审计

#### 助理（`lib/screens/tutor/`）

| 屏 | 行数 | 现状 | 病灶 | 结论 |
|---|---|---|---|---|
| `tutor_home.dart` 首页 | 1418 | `V4HeroHeader` 头图 + 5 段内容：访谈卡、五维卡、任务区、复盘卡、聊天入口 | ① 一屏 5 个「区块」，每块都有标题，主次靠滚动发现；② 27 处旧 Material 控件；③ 五维卡 5 张纵向排（`tutor_home.dart:823-833`），信息量 5×3 行却占 2 屏；④ 复盘是页内卡，做不到「点进去看明细」 | **旗舰屏**：重排 + 拆出「任务详情」「复盘」两个真页面 |
| `placement_test_screen.dart` 水平测试 | 918 | 裸 `AppBar` + `LinearProgressIndicator` 进度条（`:310-318`），intro/vocab/grammar/reading/result 5 相位 | 无 v4 头；进度条是 4px 裸条；结果页（`_buildResult`）没做「数字 + 一句话结论」的排版；空/错态是裸 `Text` | 二批：换壳 + 结果页重排（数据已现成，见 §4） |
| `tutor_chat_screen.dart` 聊天 | — | 裸 `AppBar`（`:467`）+ 气泡 | 气泡样式未走 tokens；输入区与主屏底部栏抢空间 | 二批：只换壳 |
| `tutor_interview_screen.dart` 访谈 | — | 裸 `AppBar`（`:257`）+ 选项表单 | 6 问访谈是「助理的第一入口」，却是最 Plain 的一屏 | 二批：做成「对话式卡片流」 |

#### 我的（`lib/screens/profile/` + 相关）

| 屏 | 行数 | 现状 | 病灶 | 结论 |
|---|---|---|---|---|
| `profile_home.dart` 首页 | 715 | `V4HeroHeader` + 名片 + Hero 概览 + 3 组 `AppActionTile` + 曲线卡 | 入口 9 个平铺（P8）；无「下一步」；写译记录缺位（P9） | 旗舰屏之一：重排信息架构 |
| `stats_page.dart` 学习统计 | 527 | **已经改过一轮**（`AppCard` + `SparkBars` + `RadialGauge` + 热力 + 月度），但骨架仍是裸 `AppBar`（`:55`）+ 12 处 `AppSectionHeader` | 内容不错、壳是旧的；`AppSectionHeader indexLabel` 与内页 `AppBar` 冲突；无「最近在读」以外的引导 | **旗舰屏**：换壳 + 仪表盘化（方向 A 的天然主场） |
| `weekly_report_screen.dart` 本周报告 | 800 | 裸 `AppBar`（`:263`）+ 7 个自建 `_Section`；12 处 `bodySmall/labelSmall` 裸字阶；边距 12；radius 3/8 | 自成一派，与统计页并排像两个 App（P3/P4/P5） | **旗舰屏**：改「简报」（方向 B 的天然主场） |
| `error_archive_screen.dart` 错误档案 | 625 | 裸 `AppBar`（`:186`）+ `ChoiceChip` 页签（`:241`）+ `AppTag` 来源筛选（`:309`）+ 带条数汇总（`:317-349`） | 逻辑很完整（页签/来源/汇总都有），但壳旧、页签与来源两级筛选视觉同级、每行信息只有 tag+count | **旗舰屏（内页）**：最能证明「点进去不是一坨屎」 |
| `api_settings.dart` | — | 裸 `AppBar`（`:542`）+ 10 处旧控件 | 设置类，逻辑重、视觉轻 | 二批：只换壳 + 分组 |
| `backup_screen.dart` | — | 裸 `AppBar`（`:264`）+ 10 处旧控件 | 同上 | 二批 |
| `appearance_screen.dart` | — | 裸 `AppBar`（`:31`）+ 6 处旧控件 | 同上 | 二批 |
| `bookmarks_screen.dart` | — | 裸 `AppBar`（`:488`）+ 5 处 | 同上 | 二批 |
| `widget_settings_screen.dart` | — | 裸 `AppBar`（`:85`）+ 6 处 | 同上 | 二批 |
| `writing_logs_screen.dart`（在 `lib/screens/writing/`） | 610 | 裸 `AppBar`（`:76`）+ 日期分组 + `AnimatedSwitcher` 三态 | 壳旧；但**入口不在「我的」**（P9） | 二批：先补入口再换壳 |
| `learner_preferences_screen.dart` 学习偏好（在 `lib/screens/input/`） | — | **已经是 v4**：`appbar: V4JellyAppBar`（`:222`） | 它是输入链的文件，上一轮迁移顺手带上了 | **最刺眼的组合**：在「我的」点「学习偏好」进去是新的，点其它 5 个入口进去是旧的 |
| 关于 / 更新 / 诊断 | — | 没有独立「关于」页：`诊断信息`（`profile_home.dart:300`）与 `检查更新`（`:306`）是两个 `AppActionTile`，更新走 `update_dialog.dart` | 入口权重与「学习统计/错误档案」同级 | 二批：收进「设置」组末尾，不单独设计 |

### 1.3 为什么选这 3 个旗舰屏

1. **助理首页** `tutor_home.dart` —— 使用频率最高、信息密度最大、且是「内页缺失」的源头（任务详情/复盘都是页内）。
2. **我的旗舰**：方向 A 用 `stats_page.dart`（数据最多）、方向 B 用 `weekly_report_screen.dart`（叙述最重）、方向 C 用「我的档案」（`profile_home` 的档案化）——**同一位置、三种语言**，比较最公平。
3. **内页旗舰 `error_archive_screen.dart`** —— 它同时具备：裸 AppBar + 两级筛选平级 + 只有数字没有「为什么」+ 空态最弱。是这个板块里最难也最值得先做的一屏。

> 预览图里 `assistant-*.png` 与 `detail-*.png` 是**同内容比语言**；`mine-*.png` 是每个方向各自的「我的旗舰」。

---

## 2. 三个方向

### 2.0 总表

| 维度 | A · 诊断台 | B · 每日简报 | C · 极简档案 |
|---|---|---|---|
| 一句话 | 一屏看完全部指标 | 每天早上收到一张纸 | 一本可检索的个人档案 |
| 底色 | `#F4F5FA` 冷白 | `#FBF7F0` 暖纸白 | `#F8F8F6` 纯中性 |
| 强调色 | `#4C5AF0`（果冻主色）+ 语义 3 色 | `#C4562E` 砖红 + `#2F5D50` 墨绿 | 黑 `#121212` + 琥珀 `#C2751C`（全局只有 1 处） |
| 圆角 | 卡 18 / 控件 12 | 卡 26 / 胶囊 999 | 卡 10 / 行 4 / 按钮 8 |
| 阴影 | 极浅（blur 16 / y5 / α0.05） | 暖柔（blur 26 / y10） | **无** |
| 字阶 | 数字 22/16/12 三层；标签 10.5；正文 12.5 | 40/24/19/13.5/10.5；行高 1.75 | 28/13.5/13/11.5/10.5；行高 1.6 |
| 卡片形态 | 密集白卡，卡内 3–5 行 | 少卡大卡，编辑排版（编号+线+引文） | **几乎无卡**：整页一张纸 + hairline |
| 数据可视化 | 环 + 细条 + 柱 + 热力网格（4 种） | 数字即图（26px 数字 + 一行注释）+ 7 柱 + 时间线 | 表格 + 单根分布条 + 极简网格 |
| 同屏信息量 | 7 个模块 | 5 个模块 | 6 组行 |
| 首屏「该干什么」 | 主任务卡（最大） | 开头第一句 + 主按钮 | 任务清单第一行 |
| 与输入板块连续性 | **最强**（同一批色值/圆角/阴影） | 中（大圆角+柔阴影同源，配色换暖） | **最弱**（无渐变头图） |
| 迁移成本 | 低（2–3 天） | 中（3–4 天） | 中高（4–5 天） |
| 主要风险 | 密度高→挤、冷 | 文字多→用户不读 | 撞旧版「白底黑字」观感 |

---

### 2.1 方向 A ·「诊断台」Dashboard

**一句话主张**：助理是我的私人教练仪表盘——一屏看完全部指标，数字优先，行动只有一处。

**设计语言**

| 令牌 | 值 | 说明 |
|---|---|---|
| `pageBg` | `#F4F5FA` | 果冻 `#F6F6FD` 降饱和：仪表盘底色要中性，否则指标色打架 |
| `surface` | `#FFFFFF` | 同 `V4Skin.surface` |
| `ink` / `inkSoft` / `inkFaint` | `#1C1E2E` / `#5F6478` / `#9297AC` | **直接取 `V4Skin.jellyLight`**（`v4_theme.dart:195-197`），保证与主屏同色 |
| `accent` | `#4C5AF0` | 同 `V4Skin.accent`（`v4_theme.dart:199`） |
| `good` / `warn` | `#12A06E` / `#D98600` | **新增语义色**：果冻只有「强调」，仪表盘必须有「正向/警示」两档 |
| 圆角 | 卡 18 / 控件 12 | 比果冻卡 26 更收：密度高时大圆角会糊 |
| 阴影 | `0x0D1B2140` blur16 y5 | 比 `V4Skin.shadow` 更淡，避免 7 张卡叠出灰底 |
| 字阶 | 22 / 16 / 12.5 / 10.5 / 10 | 数字三层（22 主指标、16 行值、12 环内），标签统一 10.5 w600，只有 400/600/800 三档字重 |

**旗舰屏布局（助理首页）**

```
┌──────────────────────────────────────┐
│ 9:41                    ▂▄ wifi ▮    │
├──────────────────────────────────────┤
│ 学习助理                      ⟳  ⚙   │  20/w800
│ 11月6日 周四 · 连续 6 天              │  11/inkFaint
│ ┌─────────┬──────────┬───────────┐   │
│ │ 42 个   │ 22 分钟  │ 75 %      │   │  数字 22/w800
│ │ 待复习  │ 今日计划 │ 完成率    │   │  标签 10/w600
│ └─────────┴──────────┴───────────┘   │  KPI 带（1 张白卡 3 列）
│ ┌──────────────────────────────────┐ │
│ │[今天先做]               12 分钟  │ │
│ │复习 42 个到期词                  │ │  19/w800（全屏最大字）
│ │3 天内到期 · 复习准确率 82%       │ │
│ │[    开始    ] [ 只标记完成 ]     │ │
│ └──────────────────────────────────┘ │
│ 01  现状分析                    五维  │
│ ┌──────────────────────────────────┐ │
│ │词汇      4,200  ▊▊▊▊▊▊▁▁▁      │ │  细条 3px
│ │          CEFR B1 · 距目标 800    │ │
│ │语法      62%    ▊▊▊▊▊▁▁▁▁▁      │ │
│ │阅读      148    ▊▊▊▊▊▊▊▁▁▁      │ │
│ │输出      3 篇   ▊▊▊▊▁▁▁▁▁▁      │ │  行间 hairline
│ │习惯      6 天   ▊▊▊▊▊▊▊▊▁▁      │ │
│ └──────────────────────────────────┘ │
│ 02  复盘                    近 7 天  │
│ ┌──────────────────────────────────┐ │
│ │计划 4 · 完成 3       ▁▃▂▅▄▁▂    │ │
│ │完成率 75% · 跳过 1 次            │ │
│ └──────────────────────────────────┘ │
│ ⚡ 把 42 个词拆成 2 组…         加入  │  建议行（主色 6% 底）
├──────────────────────────────────────┤
│  输入     输出     助理●     我的     │
└──────────────────────────────────────┘
```

**旗舰屏布局（我的 · 学习统计）**

```
┌──────────────────────────────────────┐
│ 我的 · 数据                    ⤴     │
│ 学习统计 · 学习节奏                   │
│ ┌─────────┬──────────┬───────────┐   │
│ │ 4,200 个│ 6 天     │ +86       │   │
│ │ 累计词汇│ 连续打卡 │ 本周新增  │   │
│ └─────────┴──────────┴───────────┘   │
│ 01  学习节奏                 近 12 周 │
│ ┌──────────────────────────────────┐ │
│ │学习打卡               每格 = 1 天 │ │
│ │ ░▓░▓ ▒▓░▒ ░▓▓▓ ▓░▓▓ ▒▓▓░ ░▓▓▓   │ │  12 周 × 7
│ │ …（7 行网格，4 档色阶 + 图例）     │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │近 7 天学习量            合计 79  │ │
│ │  ▂  ▅  ▁  ▆  ▄  ▂  ▃      ╭──╮  │ │
│ │  一 二 三 四 五 六 日       │5/7│  │ │  环 54px
│ └──────────────────────────────────┘ │
│ 02  最近在读                          │
│ ┌──────────────────────────────────┐ │
│ │The Four Million       读到 62%   │ │
│ │▊▊▊▊▊▊▁▁▁▁▁▁▁▁▁▁                 │ │
│ │CET-4 真题 2024        读到 35%   │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

**与输入板块连续性**：色值/圆角/阴影全部同源，唯一改动是把「渐变大头图」缩成
「3px 渐变细线 + 标题行」（`assistant-A.png` 顶部）。**这是 A 的代价**：头图识别度下降。
建议落地时保留 `V4HeroHeader` 的渐变，但高度从 200 收到 120，并让 KPI 带上移 40px。

**改动文件与成本**

| 动作 | 文件 | 量 |
|---|---|---|
| 新增令牌（语义 3 色 + 密度档） | `lib/config/v4_theme.dart` / `design_tokens.dart` | +40 行 |
| 新增 3 个小件：`MetricRow`（标签+值+细条）、`DeltaChip`、`KpiBand` | `lib/widgets/v4/v4_kit.dart` | +300 行 |
| 助理首页重排 | `tutor_home.dart` | 重写 build，−300/+400 行 |
| 统计页重排 | `stats_page.dart` | 换壳 + 仪表盘化，+250 行 |
| 12 个内页换壳（`V4JellyAppBar`） | 见 P1 列表 | 每屏 +8 行，纯替换 |
| **合计** | | **≈ 900–1200 行 / 2–3 天** |

**风险**：① 密度高→小屏（360dp）拥挤、误触；② 语义色扩 3 档，不进 tokens 就会页面裸写色值；
③ 视觉偏「冷」，可能削弱「学习伙伴」感（所以 A 只做主语言的一半）。

---

### 2.2 方向 B ·「每日简报」Daily Briefing

**一句话主张**：助理每天早上一张纸——今天做什么、昨天怎么样、一句提醒；像人写的，不像系统报的。

**设计语言**

| 令牌 | 值 | 说明 |
|---|---|---|
| `pageBg` | `#FBF7F0` | 暖纸白：和果冻冷白区分开，但同为浅色 |
| `ink` / `inkSoft` / `inkFaint` | `#211C16` / `#6C6259` / `#A0968A` | 暖墨色系 |
| `line` | `#EDE3D5` | 暖 hairline |
| `accent` | `#C4562E` | 砖红：主行动/日期/编号（一期最多 3 处） |
| `accent2` | `#2F5D50` | 墨绿：判断句/建议引文 |
| 圆角 | 卡 26 / 胶囊 999 | 沿用果冻的「大圆角」，这是与主屏最强的连续性锚点 |
| 阴影 | `0x14231C12` blur26 y10 | 暖柔，比果冻更轻 |
| 字阶 | 40（日期）/ 24（口号）/ 19（卡标题）/ 13.5（正文 1.75）/ 10.5（元信息）/ 9.5（眉标大写 1.6 字距） | 只 400/600/800/900 四档；**「编辑感」靠字距 + 行高 + 编号，不靠字体**（项目没有中文衬线字体，也不该为此装字体） |

**旗舰屏布局（助理首页）**

```
┌──────────────────────────────────────┐
│ 9:41                    ▂▄ wifi ▮    │
├──────────────────────────────────────┤
│ THURSDAY BRIEF               周四    │  9.5/800/字距1.6
│ 11 / 06                   连续 6 天  │  40/w900
│                                      │
│ 早上好，xi283。                      │  22/w800
│ 今天有 42 个到期词和一篇短文，大约    │  13.5/1.75
│ 22 分钟。昨天你完成了 3 件事。        │
│ ╭──────────────────────────────────╮ │
│ │今天的简报            约 22 分钟  │ │
│ │42 个词，加一篇 380 词的短文      │ │  19/w800
│ │●─ 3 分钟 · 复习                  │ │
│ ││  42 个到期词（准确率 82%）      │ │  时间线：点+竖线
│ │●─ 12 分钟 · 精读                 │ │
│ ││  《The Four Million》第二节      │ │
│ │●  7 分钟 · 回译                  │ │
│ │(   开始今天的简报   )            │ │  胶囊，砖红
│ ╰──────────────────────────────────╯ │
│ ╭──────────────────────────────────╮ │
│ │昨天                              │ │
│ │ 2 篇材料  12 个新词  82% 准确率  │ │  26/w900 数字行
│ │ 比前天高 6 个点…                 │ │
│ ╰──────────────────────────────────╯ │
│ ▍今天别一次刷完 42 个词 —— 拆成两组  │  墨绿 3px 竖线引文
│ 本周 4 天 · 86 个词      ▁▃▂▅▄▁▂     │
├──────────────────────────────────────┤
│  输入    输出    助理●    我的        │  选中 = 药丸底
└──────────────────────────────────────┘
```

**旗舰屏布局（我的 · 本周报告）**

```
┌──────────────────────────────────────┐
│ WEEKLY REPORT                 ⧉      │
│ 10.31 — 11.06                        │
│                                      │
│ 这周，你比上周多学了 1 天。           │  24/w800
│ 共 2 小时 40 分钟，收词 86 个，       │
│ 完成 3 次写译批改。晚上比上周稳。     │
│ ╭──────────────────────────────────╮ │
│ │ 2h40     86      82%             │ │  三个大数字
│ │ 总时长   新收词  复习准确率       │ │
│ ╰──────────────────────────────────╯ │
│ ╭──────────────────────────────────╮ │
│ │这周的形状                        │ │
│ │  ▂ ▅ ▁ ▆ ▄ ▂ ▃                   │ │
│ │ 周二最满(18)          周三休息   │ │
│ ╰──────────────────────────────────╯ │
│ ╭──────────────────────────────────╮ │
│ │三条要点                          │ │
│ │01 复习准确率 82%，比上周高 6 个点│ │  编号+线+段落
│ │──────────────────────────────────│ │
│ │02 写译 3 篇，均分 78；冠词最多   │ │
│ │──────────────────────────────────│ │
│ │03 周三没记录，周四因此压了 4 件  │ │
│ ╰──────────────────────────────────╯ │
│ ▍下周只改一件事：把 42 个到期词…     │  墨绿引文
│ (      复制这份报告      )           │
└──────────────────────────────────────┘
```

**与输入板块连续性**：大圆角（26）+ 柔阴影 + 胶囊按钮与果冻同源，是「同一只手换了纸」；
配色换暖需要在 `v4_theme` 加一个 `V4Flavor.warm`（或 `heroGradient`/`pastels` 的暖变体），
**不是**新建一套组件——`V4ListCard`/`V4PillButton` 等仍可复用。

**改动文件与成本**

| 动作 | 文件 | 量 |
|---|---|---|
| 暖色 flavor（`pageBg/ink/line/accent/accent2`） | `lib/config/v4_theme.dart` | +80 行 |
| 新增 `BriefCard` / `TimelineRow` / `BigDate` / `QuoteRule` | `lib/widgets/v4/v4_kit.dart` | +500 行 |
| **简报文案生成器** `TutorBriefing.build(dashboard)`（纯本地模板，不调 AI） | 新文件 `lib/services/tutor_briefing.dart` | +150 行 + 单测 |
| 助理首页重排 + 新开「任务详情 / 复盘」页 | `tutor_home.dart`（+ 2 新屏） | +600 行 |
| 周报重排 | `weekly_report_screen.dart` | 重写 body，−200/+350 行 |
| 12 个内页换壳 | 见 P1 | 每屏 +8 行 |
| **合计** | | **≈ 1200 行 / 3–4 天** |

**风险**：① **文字多是 B 的头号敌人**——必须硬性约束「每卡 ≤ 3 行正文」，否则用户根本不读；
② 简报文案是「每天一换」的承诺，模板必须有真内容（`TutorInsight.evidence` / `TutorReview.lines`
已现成，见 §4），否则会变成空话；③ 数字少，统计页会牺牲部分数据量（所以 A 的表格补在内页）。

---

### 2.3 方向 C ·「极简档案」Archive

**一句话主张**：助理和我的页是一本可检索的个人档案——只有字、线、数字和一个颜色，没有卡片和渐变。

**设计语言**

| 令牌 | 值 | 说明 |
|---|---|---|
| `pageBg` / `surface` | `#F8F8F6` / `#FFFFFF` | 极中性 |
| `ink` / `inkSoft` / `inkFaint` | `#121212` / `#5C5C5C` / `#9B9B9B` | 3 级灰 |
| `line` | `#E3E3E0` | 1px 分隔线（C 唯一的「结构」） |
| `accent` | `#121212` | **主行动 = 黑**（不靠颜色区分层级） |
| `accent2` | `#C2751C` | 琥珀：**全局只有 1 处**——「最该处理的那一类错误」 |
| 圆角 | 卡 10 / 行内 4 / 按钮 8 | 近乎直角 |
| 阴影 | 无 | 层级只靠「线 + 留白 + 字重」 |
| 字阶 | 28 / 13.5 / 13 / 11.5 / 10.5 / 10，行高 1.6 | 只 400/500/600/700；表头 10 w600 + 字距 0.8 |

**旗舰屏布局（助理首页）**

```
┌──────────────────────────────────────┐
│ 9:41                    ▂▄ wifi ▮    │
├──────────────────────────────────────┤
│ ASSISTANT / 助理            ⌕   ⋯    │  10/字距1.4
│ 学习助理                      11.06   │  28/w700
│ ──────────────────────────────────── │
│ 42         22          75%           │
│ 待复习     今日分钟     完成率        │  纯文本 + 竖线（无卡）
│ ──────────────────────────────────── │
│ 01 现状分析 ───────────────────────  │  编号 + 线
│ 词汇   4,200 · CEFR B1     距目标800 │
│ ──────────────────────────────────── │
│ 语法   62%                 近30天测验│  行 + hairline
│ 阅读   148 wpm             读完 2 篇 │
│ 输出   3 篇 / 78 分        写译 30 天│
│ 习惯   连续 6 天           每天22分钟│
│ 02 今天的任务 ─────────────────────  │
│ □ 复习 42 个到期词            12′    │
│ □ 精读《The Four Million》第二节 12′ │
│ ☑ 回译昨天那句                 7′    │
│ + 自己加一条                         │
│ 03 复盘 ───────────────────────────  │
│ 计划 4 · 完成 3 · 跳过 1       75%   │
│ 主要卡在晚上：19 点后的任务只完成 1/3。│
│ ──────────────────────────────────── │
│ 本地计算 · 数据只存这台手机 · 不花 API│
├──────────────────────────────────────┤
│  输入     输出     助理    我的      │  文字 tab + 2px 下划线
└──────────────────────────────────────┘
```

**旗舰屏布局（我的 · 我的档案）**

```
┌──────────────────────────────────────┐
│ PROFILE / 我的                  ⚙    │
│ 我的档案                             │  28/w700
│ xi283 · 学习第 118 天 · 数据只存本机 │
│ ──────────────────────────────────── │
│ 4,200        6 天        +86         │
│ 累计词汇     连续打卡    本周新增     │
│ 01 数据台账 ───────────────────────  │
│                              本周  累计│
│ 新收词                        86  4,200│
│ ──────────────────────────────────── │
│ 阅读材料                     2 篇  37 篇│
│ 复习准确率                   82%  62% │
│ 写译批改                     3 篇  41 篇│
│ 待处理错误                   7 类  23 次│
│ 02 打卡 ───────────────────────────  │
│ ░░▓░ ▒▓░▒ ░▓▓▓ ▓░▓▓ ▒▓▓░ ░▓▓▓ …     │  12×7 网格
│ 最近 12 周 · 每格 = 1 天             │
│ 03 入口 ───────────────────────────  │
│ 学习统计                     趋势/热力 ›│
│ 本周报告                    本地算    ›│
│ 错误档案                    待处理 7 类 ›│
│ 写译记录                    41 篇    ›│
│ 备份与导出                  完整备份  ›│
└──────────────────────────────────────┘
```

**与输入板块连续性**：**最弱**（无渐变头图、无彩色卡片）。落地时需要一个显式决策：
要么只把 C 用在「内页」（输入/输出主屏不动），要么在 C 里保留顶部 4px 渐变条作为唯一锚点。
预览图取的是后者（`assistant-C` 顶部无渐变，`detail-C` 也无——诚实呈现差异）。

**改动文件与成本**

| 动作 | 文件 | 量 |
|---|---|---|
| 新增灰阶 flavor + 琥珀强调色 | `lib/config/v4_theme.dart` | +60 行 |
| 新增 `SectionRule`（编号+线）/ `LedgerTable` / `TextTabs` / `ArchiveRow` | `lib/widgets/v4/v4_kit.dart` | +400 行 |
| 助理首页 + 我的档案重排 | `tutor_home.dart` / `profile_home.dart` | +700 行 |
| 列表层重写（不能复用彩色图标砖 `V4ActionTile`） | 各内页 | +600 行 |
| **合计** | | **≈ 1500 行 / 4–5 天** |

**风险**：① 用户此前明确骂过「白底 + 大黑标题 + 蓝按钮」（`docs/V4-VISUAL-REDESIGN.md:26`），
C 做不好就是**同一个观感的又一次**；② 极简全靠排版精度（字阶/字距/线对齐），
中文只有 NotoSansSC 一个字族，层级拉不开就显廉价；③ 迁移面最大，且与「果冻」需要设计裁决。

---

## 3. 推荐与取舍

### 3.1 推荐

**推荐 B（每日简报）作为两个板块的主语言，A（诊断台）作为「数据内页」的排版。**

理由（按权重）：

1. **两个板块是低频页，核心问题是「没有打开的理由」，不是「不够好看」。**
   输入/输出是「要做的事」，助理/我的是「要看的东西」——B 把「看」变成「每天一张纸」，
   这是唯一能给低频页装一个「回访理由」的方向；A 只是把「看」做得更清楚，不解决回访。
2. **B 的增量成本低于 A + C，且复用最多。** B 只需要「暖色 flavor + 4 个排版件 + 1 个纯本地文案生成器」，
   不用重写列表层；A 的仪表盘模块（KPI 带 / 细条 / 环）恰好可以嵌进 B 的「数据内页」，
   两者共用 tokens 后总成本 ≈ 5 天，而不是 3+2=5 天各做一半。
3. **C 风险最高**：撞旧版观感的概率最大，且迁移面最大；如果用户想要「冷静」，可以后续作为
   `V4Flavor.mono` 的可切换皮肤（`v4_theme.dart:21` 已经预留了 `V4Flavor.mono`），而不是主语言。

具体分工建议：

| 屏 | 语言 | 说明 |
|---|---|---|
| 助理首页 | **B** | 今日简报：一句开头 + 时间线 + 昨天 + 一句提醒 |
| 助理 · 任务详情 / 复盘 | **A** | 来查数据的人要密度，不要叙述 |
| 我的首页 | **B** 的入口 + **A** 的指标带 | 名片 + 本周摘要 + 3 个主入口 + 设置折叠 |
| 学习统计 | **A** | 天然的仪表盘 |
| 本周报告 | **B** | 天然的简报 |
| 错误档案 / 写译记录 | **A** | 天然的台账（表格 + 环 + 来源筛选） |
| 设置类（API/外观/备份/小组件/关于） | **B** 的壳 + 现有内容 | 只换 `V4JellyAppBar` + 分组，不动逻辑 |

### 3.2 三方向共同的「必做」
无论选哪个方向，以下 4 条都必须做（成本极低、感知极高）：

1. **12 个内页换 `V4JellyAppBar`/`V4DetailHeader`**（P1/P2）——组件已现成，**输入板块有 12 处现成调用可照抄**
   （例如 `material_library_screen.dart:295`），每屏 +8 行。
2. **边距统一到 `Insets.page`**（P3）——把 `weekly_report_screen.dart:292` 的 12、
   `error_archive_screen.dart:197` 的 16、`writing_logs_screen.dart:119` 的 16 全部改掉。
3. **字阶统一到 `AppFont`**（P4）——`weekly_report_screen.dart` 的 11 处 `bodySmall/labelSmall`。
4. **空态统一到 `AppEmpty`**（P10）——4 种长相收敛成 1 种。

---

## 4. 真实数据来源（哪些能直接复用、哪些要新接口）

> 结论先说：**三个方向都不需要新 SQL / 新表 / 新 AI 调用。**
> 唯一需要新增的是「文案生成器」（纯本地模板函数）和 2 个聚合字段（纯计算，不查库）。

### 4.1 统计（我的 · 学习统计 / 首页指标）

| 数据 | 来源 file:line | 字段 |
|---|---|---|
| 每日学习日志 | `lib/providers/stats_provider.dart:13`（`dailyLogs`）→ `DatabaseService.getDailyLogsInRange`（`weekly_report_screen.dart:69` 调用点） | `LearningRecord` |
| 连续天数 / 总词汇 / 总练习 | `lib/providers/stats_provider.dart:14-16` | `streakDays` / `totalVocab` / `totalExercises` |
| 加载 / 错误态 | `lib/providers/stats_provider.dart:17,20` | `loading` / `error` |
| 月度聚合 | `lib/providers/stats_provider.dart:92` | `getMonthlyStats()` |
| 打卡热力 / 7 天柱 / 环 | 已有图形组件：`SparkBars`、`RadialGauge`、`StudyCalendar`、`LearningCurveChart`（`stats_page.dart:132,193,205,249` 调用点） | — |
| 最近在读 | `stats_page.dart:112` `_ReadingInProgressCard`（内部走 `material_progress`） | 直接复用 |

**复用结论**：全部可直接复用，**无需新接口**。方向 A 只是把同一批数据换成
「KPI 带 + 细条 + 环」的排布；方向 B 的周报数字来自 §4.2。

### 4.2 周报（我的 · 本周报告 / 助理 · 复盘）

| 数据 | 来源 file:line | 字段 |
|---|---|---|
| 周报实体 | `lib/services/weekly_report.dart:248`（`class WeeklyReport`） | 项目见下 |
| 周报组装 | `lib/services/weekly_report.dart:321`（`WeeklyReportBuilder.build`） | 文案在 builder 里生成，页面不造句（`weekly_report_screen.dart:21`） |
| 取数 8 项 | `weekly_report_screen.dart:95-102`：`getReadingStats(days:7)`、`getRecentVocabularies(days:7)`、`getRecentMaterials(limit:20)`、`getQuizAccuracy(days:7)`、`getErrorTags(status:'active')`、`getReviewBuckets(now)`、`getWordReviews()`、`getTutorTasks(now)` | — |
| 逐日日志 | `weekly_report_screen.dart:69` `getDailyLogsInRange` | — |
| 未来 7 天负荷 | `weekly_report_screen.dart:242-251` `_forecastFor` → `FsrsScheduler.loadForecast` | — |

**复用结论**：B 的「本周报告」**100% 复用** `WeeklyReport` 字段 + `WeeklyReportBuilder` 文案，
只换排版；A 的「复盘」用 §4.3 的 `TutorReview`。**无需新接口**。

### 4.3 助理（首页 / 现状分析 / 任务 / 复盘 / 水平测试）

| 数据 | 来源 file:line | 字段 |
|---|---|---|
| 仪表盘一次性组装 | `lib/services/tutor_snapshot.dart:73`（`TutorSnapshotService.load`） | 返回 `TutorDashboard` |
| `TutorDashboard` 字段 | `tutor_snapshot.dart:25-48` | `snapshot` / `insights` / `suggestions` / `review` / `todayTasks` / `reviewStats` / `outputStats` |
| 五维 insight | `lib/services/tutor_insights.dart:205-228`（`TutorInsight`） | `dimension` / `title` / `valueText` / `evidence` / `actionLabel` / `actionJump` / `measured` / `severity` |
| 五维数据源 | `tutor_insights.dart:104-154`（`InsightSource`） | `vocabEstimate` / `vocabCi` / `cefr` / `dueWords` / `reviewRetention` / `errorTagCounts` / `readingWpm` / `materialsFinished30d` / `outputAttempts30d` / `outputAvgScore` / `writeLogs30d` / `streakDays` / `dailyMinutes` / `examGoals` / `goalWordsGap` |
| 维度定义 | `tutor_insights.dart:25`（`TutorDimensions`）、跳转 id `:61`（`TutorActionJumps`） | — |
| 任务建议 | `tutor_insights.dart:247-261`（`TaskSuggestion`） | `title` / `reason` / `minutes` / `action` / `goalTag` |
| 复盘 | `tutor_insights.dart:276-281`（`TutorReview`） | `lines`（文案行）、`metrics`（键：`planned` / `done` / `settled`，见 `tutor_insights.dart:921-926`） |
| 任务落库 | `lib/services/database.dart:3396`（`insertTutorTask`）、`:3471`（`completeTutorTask`）、`:3525`（`reopenTutorTask`）、`:3901`（`updateTutorTaskStatus`） | — |
| 水平测试结果 | `lib/services/vocab_estimator.dart:113-157`（`PlacementResult`：`estimate` / `low` / `high` / `cefr` / `falseAlarmRate` / `bandHitRate` / `lowConfidence`）+ `lib/services/ability_recorder.dart:17`（`AbilityRecorder` 落库能力） | 直接复用 |

**复用结论**：
- 方向 A 的「KPI 带 / 五维细条」← `InsightSource` + `TutorInsight.valueText/severity`，**无需新接口**；
- 方向 A/B 的「复盘」← `TutorReview.metrics['planned'/'done']` + `lines`，**无需新接口**；
- 方向 B 的「今天一句话 / 时间线」← `TutorInsight.evidence` + `TaskSuggestion.reason` 拼接，
  **需要一个新纯函数** `TutorBriefing.build(TutorDashboard)`（见下）；
- 方向 A 的「完成率」← `metrics['done']/metrics['planned']`，**无需新接口**。

### 4.4 错误档案

| 数据 | 来源 file:line | 字段 |
|---|---|---|
| 错误标签列表（按次数降序） | `lib/services/database.dart:3154-3176`（`getErrorTags`） | `tag` / `count` / `status` / `source` / `last_at`（排序 `count DESC, last_at DESC`） |
| 标记已改正 | `database.dart:3181`（`setErrorTagStatus`，只接受 `active`/`fixed`） | — |
| 页签 / 来源筛选 / 条数汇总 | `error_archive_screen.dart:227-315`（现成逻辑） | 直接复用 |
| 已改正的本地记忆 | `error_archive_screen.dart:173-181`（Hive） | — |

**复用结论**：方向 A 直接复用现有筛选与汇总，只换行样式（环 + tag + 来源 + 次数）；
方向 B/C 需要「最近一次」——`last_at` 已在 `getErrorTags` 返回里，**无需新接口**。

### 4.5 写译记录

| 数据 | 来源 file:line | 字段 |
|---|---|---|
| 表结构 | `lib/services/database.dart:205-249`（`writing_logs` + 索引） | — |
| 读 / 写 / 删 | `database.dart:2059`（`getWritingLogs`）、`:2054`（`insertWritingLog`）、`:2069`（`deleteWritingLog`） | — |
| 模型 | `lib/models/writing_log.dart`（`WritingLog`，含 `dateKey` 分组，`writing_logs_screen.dart:61`） | — |
| 入口 | 目前只在输出板块：`output_home.dart:18,531` | 需在「我的」补入口 |

**复用结论**：数据与页面都现成，**只缺「我的」里的入口**（纯 UI）。
方向 A 可以直接把「写译记录」做成台账行（3 篇 / 41 篇 / 均分 78），数据来自同一个 `getWritingLogs`。

### 4.6 需要新增的东西（全部不碰数据库）

| # | 需要什么 | 类型 | 量 | 为什么必须新 |
|---|---|---|---|---|
| N1 | `TutorBriefing.build(TutorDashboard)` → `headline` / `timeline[3]` / `yesterday` / `reminder` | 纯函数 + 单测 | ~150 行 | 现有 `TutorInsight` 是「维度结论」，不是「简报口吻」；B 需要一次语气转换，但数据全部来自 `TutorDashboard` |
| N2 | `TutorReview.metrics` 增加 `rate`（完成率） | 纯计算 | 3 行 | 现有键只有 `planned`/`done`/`settled`；百分比在 UI 层算也行（推荐 UI 算，连 N2 都可省） |
| N3 | 「今日已用分钟 / 计划分钟」聚合 | 纯计算（`todayTasks` 求和） | ~10 行 | B 的「约 22 分钟」必须有分母 |
| N4 | `profile_home` 增加「写译记录」入口 | UI | ~15 行 | P9 |

---

## 5. 预览图（真实渲染）

### 5.1 产出与跑法

| 文件 | 内容 | 内容与谁对比 |
|---|---|---|
| `docs/ui-preview/real/assistant-A.png` | 助理首页 · A 诊断台 | 同内容 vs B/C |
| `docs/ui-preview/real/assistant-B.png` | 助理首页 · B 每日简报 | 同上 |
| `docs/ui-preview/real/assistant-C.png` | 助理首页 · C 极简档案 | 同上 |
| `docs/ui-preview/real/mine-A.png` | 我的旗舰 · A 学习统计 | 各方向旗舰 |
| `docs/ui-preview/real/mine-B.png` | 我的旗舰 · B 本周报告 | 同上 |
| `docs/ui-preview/real/mine-C.png` | 我的旗舰 · C 我的档案 | 同上 |
| `docs/ui-preview/real/detail-A/B/C.png` | 内页 · 错误档案 | 同内容 vs 三语言 |

渲染脚本：`test/assistant_mine_preview_test.dart`

**跑通记录（2026-11-06 20:51–20:55）**：`flutter test test/assistant_mine_preview_test.dart --no-pub`
→ `00:03 +9: All tests passed!`，9 张 PNG 全部生成并**逐张肉眼复核**（中文真字体、MaterialIcons 真图标、
三方向一眼可辨、无溢出裁切；内容超过一屏的页面在底部导航上方有 44px 淡出遮罩，避免"字被切一半"的假 bug 观感）。

```bash
cd /d/readflow
flutter test test/assistant_mine_preview_test.dart --no-pub
# 产物在 build/ui_real/{assistant,mine,detail}-{A,B,C}.png（390×844 @3x = 1170×2532）
# 复制到 docs/ui-preview/real/ 后把 build/ 视为临时产物（不进 git）
```

### 5.2 关于预览的诚实说明

- **字体是真的**：测试里加载 `C:\Windows\Fonts\NotoSansSC-VF.ttf` + Flutter SDK 的
  `MaterialIcons-Regular.otf`，所以中文不会落成方框、图标是真的 Material 图标。
- **尺寸是真的**：390×844 逻辑尺寸、`pixelRatio: 3`，与已发版预览图（`material_channel_render_test.dart:214-216`）同一口径。
- **数据是假的，但字段与结构是真的**：假数据按 §4 的真实字段命名与量级造
  （4,200 词 / 42 到期 / 7 类错误 23 次 / 82% 准确率），不是占位符。
- **不是生产组件渲染**：三个方向都还没进 `lib/`，所以预览稿里的卡片/图表是在测试文件里自绘的。
  这保证了「先看图再动手」的流程，但也意味着**实现时要再对一次生产组件**（尺寸会有 ±2px 差异）。
- **只渲了浅色**：深色模式必须在方向选定后补一组渲染（`V4Skin.jellyDark` 已有的深色关系可沿用），
  这是本轮已知缺口。
- **底部导航是简化版**：真实 `ReadFlowBottomNav` 有 4 tab 的固定尺寸与玻璃底，
  预览里按各方向语言重画（A：图标+文字；B：药丸选中态；C：纯文字+下划线）——这是设计意图，不是漏画。

---

## 6. 实现计划（用户选型后）

### 阶段 0 · 地基（0.5 天）
- 把选中方向的 palette 写进 `lib/config/v4_theme.dart`（新增 `V4Flavor` 或扩 token，**不新建第二套皮肤系统**）；
- 语义色（good/warn）进 `design_tokens.dart`，禁止页面裸写；
- 补一条 `test/theme_test.dart` 断言：新 flavor 的对比度 ≥ 4.5（正文）/ 3.0（大字）。

### 阶段 1 · 12 个内页换壳（0.5 天，感知最大）
- 用 `V4JellyAppBar`（`v4_kit.dart:495`）替换 `stats_page.dart:55`、`weekly_report_screen.dart:263`、
  `error_archive_screen.dart:186`、`api_settings.dart:542`、`appearance_screen.dart:31`、
  `backup_screen.dart:264`、`bookmarks_screen.dart:488`、`widget_settings_screen.dart:85`、
  `placement_test_screen.dart:310`、`tutor_chat_screen.dart:467`、`tutor_interview_screen.dart:257`、
  `writing_logs_screen.dart:76`；
- 边距统一 `Insets.page`（P3）、字阶统一 `AppFont`（P4）、空态统一 `AppEmpty`（P10）。

### 阶段 2 · 助理旗舰（1–1.5 天）
- 首页按所选方向重排；
- **新开两个真页面**：「任务详情」（替代 `showModalBottomSheet`，`tutor_home.dart:1044-1123`）、
  「复盘」（替代页内卡 `:431-436`）；
- 任务详情必须带：为什么（`reason`）、开始/完成/跳过/撤销/编辑、相关数据（`target_minutes` / `goalTag`）。

### 阶段 3 · 我的旗舰（1–1.5 天）
- 首页信息架构重排（P8：数据入口 > 配置入口），补写译记录入口（P9）；
- 统计 / 周报 / 错误档案按 §3.1 的分工重排。

### 阶段 4 · 收尾（0.5 天）
- 深色模式渲染复核（新增 1 组预览图）；
- `flutter analyze` + 全量 `flutter test`（1577+ 用例）；
- 按 `docs/V4-VISUAL-REDESIGN.md:61-68` 的 6 条验收逐屏打勾。

### 验收（每屏都要过，取自 `V4-VISUAL-REDESIGN.md`）
1. 有主题色/彩色头图或色块，不是白底一片；
2. 主次分明（标题 > 内容 > 元信息），一眼知道点哪；
3. 加载/空/错误三态齐全且同一套长相；
4. 颜色/圆角/字号/间距全部走 tokens（`rg 'fontSize: [0-9]' lib/screens` 应只剩 tokens 调用）；
5. 内页与主屏同一视觉语言（`rg 'AppBar\(' lib/screens/profile lib/screens/tutor` 应为 0）；
6. 深色可用、对比度达标、「减少动态效果」生效。

---

## 7. 本轮明确不做

- 不改 `lib/` 任何生产代码（本文件与预览图是唯一新增物）；
- 不动数据库（dbVersion 保持 22）、不加表、不加 AI 调用；
- 不做听力（用户明确不做）；
- 不改 `pubspec.yaml`、不装依赖、不 commit；
- 不渲深色与窄屏（360dp）——列入阶段 4。

---

## 附：预览图与代码的对应关系

| PNG | 预览类 | 对应未来生产屏 |
|---|---|---|
| `assistant-A.png` | `_AssistantA` | `tutor_home.dart`（方向 A 重排） |
| `assistant-B.png` | `_AssistantB` | `tutor_home.dart`（方向 B 重排）+ `tutor_briefing.dart` |
| `assistant-C.png` | `_AssistantC` | `tutor_home.dart`（方向 C 重排） |
| `mine-A.png` | `_MineA` | `stats_page.dart` |
| `mine-B.png` | `_MineB` | `weekly_report_screen.dart` |
| `mine-C.png` | `_MineC` | `profile_home.dart` |
| `detail-A/B/C.png` | `_DetailA/B/C` | `error_archive_screen.dart` |
