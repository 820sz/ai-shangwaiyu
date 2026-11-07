# QA 第三轮验收清单 · v2.28.0 · 真机反馈 8 条（前半：可勾选清单 + 静态基线）

> 任务卡：`task-18`。来源：`docs/ROUND3-PLAN-2026-11-07.md`（8 条根因/修法/分工）、
> `docs/ACCEPTANCE-GUIDE-v2.27.0.md`（真机背景）+ 任务板 task-12~17 的可验收要求。
> **当前状态：6 条线 WIP（工作区未提交），本文件先立清单；§9 结论章节等各线交付/Lead 转告后填。**
> 图例：☐ 未验 · ◐ 进行中/部分 · ☑ 通过 · ✗ 退回（P0）。纪律：每条必须有「file:line + 渲染图 read_image + 定向测试数字」三重证据，
> 只有测试绿不算过；有 TODO/占位/写死假数据即 ✗。

## 0. 通用闸门（round3 版，8 条都必须过）

| ID | 判据 | 验证方式 | 状态 |
|---|---|---|---|
| G1 | 每条给 **file:line + 渲染图（read_image 实看）+ 测试数字**，缺一不判通过 | 报告逐条列 | ☐ |
| G2 | `bash tool/lockrun.sh analyze --no-pub` 相关目录 = **0 error / 0 warning**（存量 info 不算） | 贴原始输出 | ☐ |
| G3 | 相关测试全绿且**无旧测回归**；新交互有 widget/纯函数测试 | lockrun 记录 passed/failed | ☐ |
| G4 | 无 TODO/FIXME/占位/「后续再做」/写死假数据（渲染测试 fixture 除外，需注明） | grep + 读代码 | ☐ |
| G5 | 跨作用域改动**逐条记录**（文件+原因+批准）；未记录即 ✗ | diff 对照写作用域表（ROUND3 §1） | ☐ |
| G6 | 渲染图**逐屏**（不是一张代表图）、390×844@3x/真字体，命名可追溯 | 清点 PNG + read_image | ☐ |
| G7 | 不 commit/push、不改 pubspec 依赖（PDF 除外需先批准）、不改 dbVersion（除非批准）/DB 结构；版本最后统一到 `2.28.0+93` | git status + diff | ☐ |
| G8 | **上一轮已验收项无回退**（关键不变量见 §1.0） | 抽验代码+渲染 | ☐ |

## 1.0 回归检查点（上一轮 QA 通过项，本轮改动不得破坏）

| 主题 | 不变量（抽验即可，发现破坏记 ✗） |
|---|---|
| 找材料 | 频道页 4 组结果件/每页 10 条/页码/继续找更多/快照 `free:<词>`·`need:all`；旧 AI 找材料页**零活入口**（v2.27.0 修）；free 5 类型+9 来源+难度「按来源预估」；need 4 行「待测」不出数字、级别 2 仅在有 analysis 时出现；D6 历史可清空/回填 |
| 阅读器 | 零常驻按钮（无 AppBar/FAB/旧动作栏）、42px 把手、三纸色卡持久化、只**生词**砖红下划线、进度落库 ≤99 且 finished=100、续读按 percent、44px 纸色安全条（不压字）、查词弹层纸色无蓝 |
| 助理/我的 | 12 内页 `V4JellyAppBar`、B 简报两首页真实内容、`TutorBriefing/MineBriefing` 接线、任务详情/复盘两页、写译入口、空态统一 `AppEmptyState`、名片 B 语言三栏 |
| 输出 | 四阶设置/答题/批改/题库/写译/计划 A 纸面；`parsePaperMeta` 只认命中不猜；`paper_year/paper_label` 落库 0 迁移；题库等级筛选真查库；`resolveExamType` 材料出题吃筛选；9 图口径 |
| 上轮小修 | 输入双横杠已消（统一系统 handle）、识图「已校验」行 Flexible 换行、无封面卡不画假封面、书架 3D 不得回退成「原版书」渐变假封面 |

## 0.1 当前工作区快照（2026-11-07 12:15，静态盘点；各线 WIP 未提交）

- 版本：`pubspec 2.27.0+92`（计划目标 `2.28.0+93`，打包前统一改）；`git log` 最新 `33c244a`（v2.27.0 重建/文档）。
- W1a（材料中心搜索）已见：`material_discovery.dart +70`、`content_quality.dart +267`、`material_taxonomy.dart +184`、`material_channel_screen.dart`、`need_search_screen.dart +46`；新测试 `test/material_channel_query_test.dart`、`test/need_search_reason_test.dart`，`content_quality_test.dart +188` → ◐。
- W1b（自由搜/封面）**未见代码**：`lib/services/material_ai_rewrite.dart` 不存在、`free_search_screen`/`material_result_list` 未在 diff → ☐ 未开始/早期。
- W2（书架 3D）已见：`shelf_carousel_view.dart` 大改（+354/-?）、`bookshelf_views_test +78` → ◐（shelf_cover_grid 未在 diff，需确认文字卡兜底未动）。
- W3（阅读器）已见：`material_reader_screen +92`、`reader_progress +128`、`reader_action_bar`、`reader_c_render_test +10`、`reader_c_widget_test +25`、改前对照图 `reader-c-before-first.png`/`reader-c-before-scroll.png` → ◐。
- W4（输出）**未见代码改动**（output_* 未在 diff；`继续上次练习`/draft 未出现在 output 代码）→ ☐ 未开始/早期。
- W5（我的/关于/开屏）已见：新 `about_content.dart`/`about_notice.dart`/`about_doc_screen.dart`/`about_notice_screen.dart`/`about_notice_gate.dart`；`about_screen.dart` 已有「01 关于软件（三入口）+ 开源许可（showLicensePage）」，`about_content.dart:17/23/29` 引用的三个 md 与 `assets/about/` 实际文件**完全一致**；`app.dart` 已接 `AboutNoticeGate`（:62）；`assets/about/` 三份 md 共 ~25KB（12:01-12:05）；`pubspec` **仅 +1 行 = `assets/about/` 声明、无新依赖**；`profile_name_card.dart +30`/`profile_home.dart +30`；新 `test/profile_about_test.dart` → ◐。
- 待核风险（各线交付时逐条验）：① W1a 检索词纯函数单测是否真证明 `direction!=need` 不含 goals；② W2 初始态是否真不渲染抽出封面（不是靠 z 序压住）；③ W3 正文宽度数字是否给出且进度不遮挡文字；④ W5 开屏公告只弹一次是否用 Hive 标记且有测试；⑤ 内容 md 的真实文献链接是否可达/非编造。

---

## 1. 材料中心频道页搜索质量（W1a：task-12）

**用户症状**：首次找材料相关性太弱/无用；语言混乱（出现越南语）；搜真题分不出四级/六级、搜出考试报名网；AI 被"用户需求"框太死。
**修法（计划/任务卡）**：频道页检索=**分类 queries + 难度档**，`direction != need` 时彻底不注入 `_need`（goals/needSummary）；补三层过滤（非英文/公告报名页/弱相关）；真题 queries 拆 CET-4/CET-6 并给卡片打级标；覆盖率 0%（极低）不出「为什么推」。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 1.1 | 纯函数单测证明：`direction != need` 时 **queries 不含任何 goals/needSummary/需求摘要**，只含分类 queries+难度档；`direction == need`（按需求/找材料按需找）**保留**需求参与 | `test/material_channel_query_test.dart`（已存在）+ 纯函数 file:line；给出改前/改后检索词示例 | ☐ |
| 1.2 | 非英文过滤生效：**越南语样例**被判非英文丢弃（纯函数单测）；英语正常文章不误杀 | `content_quality.dart` 新过滤器 + 单测（`content_quality_test.dart` 已加行）；需见越南语样例断言 | ☐ |
| 1.3 | 公告/报名/考试简介/培训/官网类页面被过滤（关键字/URL 规则），真题正常页不误杀 | 新过滤器 file:line + 单测 | ☐ |
| 1.4 | 弱相关过滤：标题+摘要与分类/检索词无命中 → 丢弃（单测） | 同上 | ☐ |
| 1.5 | 真题 queries 分 **CET-4 / CET-6** 两组（`material_taxonomy.dart`），结果卡按标题/URL 推 level 标签；「四六级」泛化不吞并明确级 | taxonomy file:line + 单测/代码；渲染或纯函数证据 | ☐ |
| 1.6 | 覆盖率 0%（或低于阈值）**不显示**「为什么推:难度 0%」；频道页同类文案同口径 | `need_search_screen._reasonFor` 阈值 file:line + `test/need_search_reason_test.dart`；渲染对照 | ☐ |
| 1.7 | 需求过滤只影响「找材料·按需找」，频道页（按题材/形式/场景）行为符合用户原话「只按难度+分类」；给出对照说明（改前/改后检索词示例） | 对照示例写进各线简报 + 本报告 | ☐ |
| 1.8 | 回归：频道页分页/继续找更多/快照/「我的」方向级 key 未回退（§1.0） | 代码抽验 + 定向测试 | ☐ |

**涉及文件**：`lib/services/material_discovery.dart`、`content_quality.dart`、`material_taxonomy.dart`、`lib/screens/input/material_channel_screen.dart`（query/needText/理由）、`need_search_screen.dart`（理由阈值）、test/ 对应。
**渲染/证据**：检索词对照（文本即可）+ 若频道页出现新过滤提示需图。**当前 WIP 已见**：content_quality +267、material_discovery +70、taxonomy +184、channel/need_search 改动、新测试 2 个 → ◐ 待交付验证。

### 1.9 W1a 复核结论（首轮，2026-11-07 12:5x；测试数字待锁空后补）

- **根因口径修正（记入报告）**：真正泄漏点不是 `_buildQueries` 的 queries 数组（旧实现本来只有分类词），而是 ① 频道 `needText` 非 need 方向拼了「我的需求:…」当 `userQuery`；② `planNextQueries`/补救轮用 `_prefs.promptHint`（含目标/兴趣/补充要求）。→ 修法方向正确。
- ✅ 检索词口径：`material_taxonomy.dart:262 buildChannelQueries`（非 need 只 `categoryQueries`，:272-280）、`:296 buildChannelPromptHint`（只「分类+难度」，need 返回空串 :302）；频道页接线 `material_channel_screen.dart:542/:554`，discover 传 `promptHintOverride/categoryHint`（:865/:866）✓。单测 `material_channel_query_test.dart` 有明确断言：非 need 方向对 `四六级/雅思/science/只看真题` 一律 `isFalse`（:24-30），need 方向仍含需求（:58-69），promptHint 不含「目标:四六级」（:100-102）✓。
- ✅ 三层候选过滤：`content_quality.dart:363 looksLatinNonEnglish`（中文占 8+ 或 cjk≥latin 直接放行→中文真题不误杀，:382-383）、`:407 looksLikeAnnouncementPage`（中文/英文信号+URL 路径）、`:434 isWeaklyRelated`（rerank>0 或 authority≥2 直接信任，:442）；`rejectCandidate:463`。接入**抓取/付费之前**（`material_discovery.dart:287-290`），notes 透明汇总（:458-467）。集成测试 `material_discovery_batch_test.dart:467`「越南语/报名公告/弱相关被过滤,不占抓取名额」以假 transport 证明"正常真题通过、坏候选不进抓取" ✓。
- ✅ 真题分四级/六级：taxonomy form 子分类含 `cet4/cet6/exam`（测试 :118-136 断言 label/queries 不互串）；`examLevelOf:333`（四六级并存→空串不猜）、`examLevelTag:357`；频道卡 :104 加级标 ✓。
- ✅ 理由阈值：`need_search_screen.dart:881 needSearchMinReasonCoverage=0.10`、`:893 coverage==null || <0.10 → null`；`need_search_reason_test.dart` 覆盖 0/5/9% 不显示、96% 显示、阈值边界 ✓。
- ✅ **P3-1 已关闭**：`docs/ui-preview/real/channel-*.png` 已同步（13:11 五张 + 新增 `channel-form.png`/`channel-filtered.png`），与 build 版本一致。
- ✅ **P3-2 已关闭**：`channel-form.png` 实看=9 chips（全部/教材/书籍/外刊/论文｜四级真题/六级真题/全部真题/碎片文章｜其他），等级筛选达成；CET-4 卡来源胶囊带「四级真题」级标 ✓。**新 P3（视觉小 nit）**：「其他」孤零零占第三行 → 建议缩 spacing 或与「碎片文章」并排（可选）。
- ✅ **P3-3 已关闭**：`channel-filtered.png` 实看 meta 行第二行出现「已过滤 3 条质量不合格的候选(公告/报名页 1 条、非英文内容 1 条、与分类弱相关 1 条)。· 已过滤 4 条质量不合格…」→ notes 汇总确在结果说明里；**新 P3**：两轮 notes 各报一次（3 条 / 4 条）且第二句被 maxLines=2 截断（"…"）→ 建议合并成一条总数或缩短模板。
- 结论：**W1a 静态/图/单测内容全部成立，标 ☑（P3 已消化为 2 条可选项）**；定向测试数字仍待锁空补。

## 2. 阅读器空间利用率（W3：task-15）

**用户症状**：阅读器排版"太低"、右侧留白多、正文列窄（真机截图）。
**修法**：右侧 96px 竖轨+%胶囊改为**悬浮叠加在右侧留白**（不挤压正文，正文只留 8~12px 安全区）；左右/上下 padding 收紧；保持 18/1.8 与 C 全部特征；出改前/改后对照渲染。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 2.1 | 竖轨/胶囊不再占用正文布局宽度（`Stack`/`Positioned` overlay），正文右侧让位从 46 降到 ≤12（或等价实现） | reader screen/progress file:line + 实测数字 | ☐ |
| 2.2 | **改后正文宽度 vs 改前数字**（390 宽下具体 px 或列表 padding 前后值） | 各线简报给数字；本报告记录 | ☐ |
| 2.3 | 左右/上下 padding 收紧且首屏信息量提升；刊头/底部把手间距合理 | diff file:line + 图 | ☐ |
| 2.4 | C 特征不丢：零常驻按钮/42px 把手/刊头双线/三纸/只生词下划线/进度%/控制台 4 组/44px 安全条 | 代码+图+旧测试 | ☐ |
| 2.5 | **改前/改后对照渲染**逐张 read_image（首屏+滚动中；控制台/设置不回归） | `reader-c-before-*` + 新图 | ☐ |
| 2.6 | 进度显示仍随滚动连续、正文不被进度组件遮挡（滚到任意位置文字不压） | 图 + widget test（正文宽度不因进度变化） | ☐ |
| 2.7 | 回归 29 项旧功能 + reader_c_* 全绿 | lockrun | ☐ |

**涉及文件**：`lib/screens/input/material_reader_screen.dart`、`lib/widgets/reader_progress.dart`、`reader_action_bar.dart`、`reader_console/sheets/paper`、`test/reader_c_*`、`docs/ui-preview/real/reader-c-*.png`。**当前 WIP 已见**：reader screen +92、reader_progress +128、before 图 2 张、reader 测试 +10/+25 → ◐。

### 2.9 W3 复核结论（首轮，2026-11-07 13:0x；测试数字待锁空后补）

- ✅ 布局数字自洽：列表 padding `26/8/46/30 → 16/4/20/18`（`material_reader_screen.dart:2241`）→ 390 宽正文 = 390−16−20 = **354px**（旧 318，+11.3%，与交付声明一致）；`test/reader_c_layout_test.dart` 断言 `passage.width closeTo(354,1)`、竖轨 `3×96`、轨道与文字间距 ∈[8,16]、胶囊在正文上方（:112-131）。
- ✅ 竖轨不再挤压正文：`reader_progress.dart` 注释 + `ReaderProgressRail` 改 3px overlay（`Positioned(right:4)`，叠在 20px 右 padding 的 10px 安全区上）；% 胶囊移到顶部 40px 条右侧 `ReaderProgressBadge`（`material_reader_screen.dart:2307`）✓。
- ✅ **before/after 实图对比成立**（read_image 逐张）：同一段首段行数 5 行 → **4 行**（每行更多词）；scroll 对比（同为 37%）after 屏底多出**一整个段落**（"Managers can help by making the quiet block visible…"），确认"同屏多一段"；正文左边界明显左移（16 vs 26）。
- **3px 竖轨判断（按 QA 建议已落实，收尾确认）**：`reader_progress.dart:50 trackColor()` = 墨色 18% 混纸底（不新增第 4 色令牌，三纸自动一致），`:79` 轨道底色改用它；3px 宽/9px 热区/控制台 3px 条均不变。**13:11 新版 `reader-c-after-first.png` 实看：0% 时轨道为可辨识的深灰细线**（对比 before-first 的 1.23:1 几乎不可见明显改善）；`reader_c_paper_test` 新增守门：track 对纸底 ∈[1.35,2.6]、砖红对 track ≥2.5、track ≠ hairline（测试文件 :64-79）。**结论：保持 3px、轨道可辨识 ✓**。
- ✅ C 特征无回退（图+代码抽验）：零常驻按钮（无 AppBar/FAB，底部 2px 线+42px 把手「37% 已读/抓手/上滑工具」）、刊头双线、三纸（paper-night 新版：墨夜+提亮砖红+只生词下划线可读）、只生词砖红下划线（remedy/unglamorous/multitasking/distracted）、控制台 4 组且 `console-material` 滚到底材料组完整不裁。
- ✅ 交付物同步：`docs/ui-preview/real/` 17 张 reader-c-*（13 标准 + before/after 各 2）13:11 全部按新轨道色重出（与 13:11 channel 图同批）。
- 结论：**W3 标 ☑（3px 保持 + 轨道可辨识 + 前后对比成立 + C 特征无回退）**；定向测试数字仍待锁空补。

## 3. 书架 3D「横档」封面（W2：task-14）

**用户症状**：每次点进书架 3D 都有一本书「横档」在前面（抽出的封面初始就渲染/遮挡书脊）。
**修法**：初始态只显示一排书脊（无抽出封面）；点书脊才抽出、再点/点空白收回；滑动行为保持；详细网格不受影响。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 3.1 | 初始态（未点选）**无抽出封面卡**、无遮挡书脊；底部 hint 正常 | 图 `shelf-*initial*` + read_image + 代码 file:line | ☐ |
| 3.2 | 点书脊 → 该本抽出显示封面且**不遮挡相邻书脊**；再点/点空白 → 收回 | 渲染 2~3 张 + widget test | ☐ |
| 3.3 | 左右滑动/选中切换行为保持；详细书架网格无回归 | 测试 + 图 | ☐ |
| 3.4 | 不得回退成「原版书」渐变假封面（无真封面仍文字版式） | §1.0 抽验 | ☐ |
| 3.5 | `bookshelf_views_test` 更新（初始无抽出/点书脊出现/再点收回）+ analyze 0/0 | lockrun | ☐ |

**涉及文件**：`lib/widgets/shelf_carousel_view.dart`、`shelf_cover_grid.dart`、`test/bookshelf_views_test.dart`、`docs/ui-preview/real/shelf-*.png`。**当前 WIP 已见**：carousel +354 行、测试 +78 → ◐。

### 3.9 W2 复核结论（2026-11-07 14:0x）

- ✅ 初始态**没有抽出封面**：`shelf_carousel_view.dart` 抽出封面有独立 Key `featuredCoverKey`（:51）+ `_selected = null` 表示未抽出（:66）；初始只滚到中间、不选中（:82-84）。图 `shelf-carousel-initial.png` 实看=一排书脊 + 空搁板 + hint「左右滑翻书 · 点书脊抽出封面 9 本」，**无横档** ✓。
- ✅ 点书脊才抽出：图 `shelf-carousel-open.png`：Moby Dick 封面浮在书架排**上方**（不覆盖任何书脊/hint），hint 变「点书脊收回 · 点封面打开 · 左右滑翻书 2/9」；抽出封面定位 `bottom: _bookBottomGap + 4` 与书脊排错开（:20）。再点/点空白收回（:13 注释 + 测试断言）。
- ✅ 滑动行为：`shelf-carousel-swiped.png` 4/9 时封面跟着"当前选中本"（Walden）悬在其正上方；「左右滑只滚书脊、不自动抽出」的修复语义保留（初始态滑动不会拉出封面）。
- ✅ 测试 `bookshelf_views_test` **+2 passed**（含“初始态没有抽出封面”Key 断言）；analyze 0/0；无回退假封面（无真封面仍文字版式）。
- ✅ 图已同步 `docs/ui-preview/real/shelf-carousel-{initial,open,swiped}.png`（14:00）；旧 `shelf_carousel.png`/`shelf_detail.png` 下划线重复图已删除（清理正确）。

## 4. 自由搜 UI 修复 + AI 改写保底（W1b）

**用户症状**：① 顶部输入框字体被裁；② 筛选分类悬置挡大半个屏幕不能收起；③《原子习惯》等搜不到原文时只给无关材料，需要「AI 基于搜索信息改写版 + 说明 + 来源」。
**修法**：修 TextField 布局（minHeight/contentPadding 不裁字）；筛选默认**收起**（顶部「筛选(n)」+已选摘要 chips，可展开/收起）；无结果/不足时 DeepSeek 基于已搜标题+摘要+来源生成**明确标注「AI 改写学习版（非原文）」**材料（可读/保存，含基于哪些来源）；有原文优先、不混淆。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 4.1 | 输入框文字**不裁切**（含中文/长词/光标），390 宽渲染逐张看 | 图 + 代码（TextField 布局） | ☐ |
| 4.2 | 筛选默认收起；有「筛选(n)」按钮 + 已选摘要 chips；展开/收起可用且不遮结果 | 两态渲染 + 代码 | ☐ |
| 4.3 | 无结果/不足 → 出「AI 改写学习版」：卡片/详情明确标注「非原文」+ 说明「基于哪些来源」+ 来源列表；可阅读/可保存 | 渲染 + 单测（`material_ai_rewrite.dart` 纯逻辑/降级） | ☐ |
| 4.4 | 有真实原文时**优先原文**、不改写混淆；改写仅作保底且状态可区分（标签/存储字段） | 代码 + 测试 + 图 | ☐ |
| 4.5 | 改写失败/无 Key 时如实降级（提示不可用，不出假内容） | 测试/图 | ☐ |
| 4.6 | 回归：free 5 类型/9 来源/分页/继续找更多/历史（§1.0） | 抽验 | ☐ |

**涉及文件**：`lib/screens/input/free_search_screen.dart`、`lib/services/material_ai_rewrite.dart`（新）、`lib/widgets/material_result_list.dart`（封面/改写卡）、test + 图。**当前 WIP 已见**：尚未在 diff 中看到（`material_ai_rewrite.dart` 不存在）→ ☐ 未开始/早期。

## 5. 封面懒加载（W1b，与第 4 条同线）

**用户症状**：材料中心封面又没了（能爬到封面/插图就该显示，没爬到才文字卡）。
**修法**：卡片级**懒加载封面**（imageUrl 空 → 异步轻量抓 og:image，有缓存、失败静默不出假图）；抓正文时回填（已有）；书目类用 coverFor/Gutenberg；出「有封面/无封面」两种卡；书架/我的同口径。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 5.1 | 有真封面 → 显示真图；无 → 纯文字卡（不画渐变假封面） | 有图/无图对照渲染 + read_image | ☐ |
| 5.2 | 懒加载：imageUrl 空时异步抓 og:image；**有缓存**（同 URL 不重复抓）；**失败静默**（无图→文字卡，不蹦错误/不占位假图） | 代码 file:line + 单测（缓存命中/失败降级） | ☐ |
| 5.3 | 抓正文时回填 imageUrl 生效；Gutenberg 类书目用 coverFor 封面 | 代码 + 测试/图 | ☐ |
| 5.4 | 书架 3D/网格、「我的」卡同口径（真封面才显示；文字版式兜底） | 图 + 抽验代码 | ☐ |
| 5.5 | 不引入新依赖/不破坏离线（抓图失败不阻塞列表） | diff + 代码 | ☐ |

### 4.9 W1b 自由搜复核结论（2026-11-07 14:0x）

- ✅ **输入框不裁字**：`find-material-impl-free-input.png` 实看「原子习惯 atomic habits 与微」完整含光标/x/搜索钮；`find_material_free_search_test 12 passed` 覆盖该布局。
- ✅ **筛选默认收起/可展开/搜索后自动收起**：input 图=收起态「筛选 ∨ 来源·类型·难度·场景」；`free-filters.png`=展开态（来源 9 个/类型 5/难度 4 + 「收起筛选」）；代码 `_filtersOpen=false` 搜索完成后（free_search:引用 setState `_filtersOpen = false`）→ 结果出来自动收起 ✓；展开不遮结果（图可见结果区）✓。
- ✅ **无结果真实原因**：`ai-empty.png` 显示「这次没找到能读的结果」+ 搜了什么/命中几条/源怎么说/为什么没抓到正文（可操作）✓，不是只一句"再搜一次"。
- ✅ **AI 改写保底链路**：`ai-generated.png`：独立卡「AI 改写学习版(非原文)」+ 标题/中文名 + 说明「基于你这次搜到的线索改写…不是原文」+ 全文 180 词/覆盖率 96%/CEFR B1/约 3 分钟 + 「基于 2 条真实来源」列标题+来源 + 声明「入库标题带标注,不会和原文混」+ 开始读/保存到我的/重新生成 ✓。UI 结构：AI 兜底区在**结果列表下方**（`free_search` `_children`: 结果 → `_aiFallbackSection`），有原文时文案「这些都不合适？如果有原文，优先读上面的结果」→ **不自动替换** ✓（Lead 防注水点 ① 成立）。
- ✅ **AI 改写服务**：`material_ai_rewrite.dart` 单测 **21 passed** 覆盖：线索为 0 不调模型（:294）、模型编造 URL/来源只映射真实候选（:166/:182）、字数用本地实数替换模型自报（:311/:368）、标题永远带标注且无 Markdown 星号（:99/:106）、正文末尾来源链接+非原文+许可三者缺一不可（:243）✓。
- ✅ 交付物：`find-material-impl-*` 17 张 13:51 已同步 docs；`find_material_render_test 17 passed`。

### 5.9 W1b 封面复核结论（2026-11-07 14:0x）

- ✅ **有图/无图两态真实**：`cover-with.png` 卡片左侧 58×76 圆角缩略图（真封面、右侧文字不变）；`cover-without.png` 纯文字版式（标题+来源/类型/难度），**不画渐变假图** ✓。
- ✅ **懒加载/缓存/失败静默**：`material_result_list.dart:444-560`：同 URL 去重（`_entries[url]`、in-flight 表）、只接受 http(s)（:507-510）、失败写 `null` + debugPrint 静默（无假图）；`httpMaterialCoverProbe` 单次轻量 GET + 超时；取图顺序 ①数据 imageUrl ②公版书按书号现算(Gutenberg 官方封面,零网络) ③卡片级懒加载 og:image（图内说明一致）。
- ✅ 单测 `material_result_list_test 21 passed`（有图直显/失败保文字/同 URL 只抓一次/公版书零网络/脏 URL 丢弃）。
- ✅ 书架/我的同口径：书架无真封面仍文字版式（W2 已验）；`shelfCoverHasImage` 复用。

## 6. 输出四项（W4）

**用户症状**：① 四阶卡字体被裁；② CET-6 材料显示 `cet4_writing` rubric 且 UI 显原始 id；③ 材料不能切换/必须按顺序做题；④ 练习材料退出不留存、下次重新找。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 6.1 | 四阶卡**不裁字**（中文/长副标题 2 行完整）；渲染逐张看 | 图 `output-impl-home*` / output_tier_card + 代码 | ☐ |
| 6.2 | CET-6 材料选 **六级中文 rubric 名**（如「六级写作/翻译」），不再显示 `cet4_writing` 原始 id；CET-4/其他等级对应正确 | 渲染 + 单测（exam_type→rubric 映射/中文名） | ☐ |
| 6.3 | rubric seed **幂等补**（INSERT OR IGNORE/等价），老库也生效（不要求迁移） | 代码 file:line + 测试（重复 seed 不炸、老库可读） | ☐ |
| 6.4 | 答题页**可自由跳题**（上一题/下一题 + 答题卡/列表任选），不强制顺序；提交仍整组 | widget test + 渲染 | ☐ |
| 6.5 | 生成题组即落库为**草稿**；输出首页/练习中心有「**继续上次练习**」入口；退出重进可恢复（含进度/已答） | 测试（落库/恢复）+ 渲染 + 代码 | ☐ |
| 6.6 | 不新增 DB 列/不改 dbVersion（如需，先 Lead 批准并记录）；rubric seed 写在现有表 | diff + 代码 | ☐ |
| 6.7 | 回归：P0-1 来源行三处 / 等级筛选真查库 / `resolveExamType` / A 纸面 9 图口径（§1.0） | 抽验 | ☐ |

**涉及文件**：`lib/screens/output/**`、`widgets/output_tier_card.dart`、`practice_flow/history/setup`、`lib/services/output_*.dart`、`database.dart`（仅 rubric/paper）、test/output_*、图。**当前 WIP 已见**：尚未在 diff 中看到 → ☐ 未开始/早期。

### 6.9 W4 输出复核结论（2026-11-07 14:0x）

- ✅ **四阶卡不裁字**：`output_impl_render_test 10/10`；图 `output-impl-home.png`（14:00）实看四阶 01-04 卡标题/副标题完整一行、无溢出裁切；代码 `output_tier_card.dart:112 Expanded` + `:125 Flexible` + 副标题 `maxLines:2` —— 文字区用 Expanded 吃剩余高度，**不是固定高硬切**；注意：更长副标题超 2 行仍会省略号（设计上的 textOverflow，不是裁切），当前真实内容 1 行完整。
- ✅ **CET-6 → 六级中文 rubric 名**：`output_rubric.dart:256-257` `cet6_writing:'六级写作评分标准'`、`cet6_translation:'六级翻译评分标准'`；`:282` 按 isTranslation 选；图 `output-impl-answer-cet6.png`（14:00）实看「批改标准 六级写作评分标准」+ 5 维 chip（内容切题25/组织连贯20/语言准确25/词汇丰富15/句式多样15），**未显示原始 id** ✓。
- ✅ **rubric seed 幂等补 + 老库生效**：`output_rubric.dart:482-530` 新增 `cet6_writing`/`cet6_translation` 两套；`database.dart:961/984-994/1132` 用 **INSERT OR IGNORE + 固定 id** 在开库自检里补种（老库开库即补，**零迁移/不加列**，`git diff database.dart` 无 ALTER/ensureColumn）✓；定向测试包含 rubric 6 套的断言。
- ✅ **答题可自由跳题**：`practice_flow_screen.dart:310 上一题`、`:347-368 答题卡（整组一览，当前/已批改/已写/未答，点任意题跳转）`、`:544 tooltip 答题卡（可跳题）`；`practice_flow_test.dart:169`「答题卡：可跳到任意题，答题草稿随题切换不丢」通过 ✓；图 answer-cet6 底部可见「← / 提交批改 / 答题卡」三件。
- ✅ **题组草稿落库 + 继续上次练习**：`output_draft.dart` Hive 单行 JSON（key `output_draft_v1`:126，save:149）；`output_home.dart:493-503`「继续上次练习」卡（仅草稿存在且题组可还原才显示，失败静默隐藏 :110）；图 home 实看「继续上次练习：英语六级(CET-6)·2023年12月第1套·写作真题·第2/2题·已写1题」✓；`practice_flow_test.dart:218`「继续上次练习：按草稿恢复题号与作答」通过；`output_draft_test 8 passed`（保存/覆盖/清空/坏数据容错/越界/题型映射）。
- ✅ 测试：`output_impl_render_test 10/10`、W4 定向 12 passed（practice_flow+output_draft）；图 10 张 14:00 同步 docs；无 TODO/占位/写死假数据。
- P3（证据小缺口）：`output-impl-answer-cet6.png` 截取位置看不到题干（主图 `output-impl-answer.png` 有题干/作答区），建议补一张含题干的 CET-6 答题图或注明滚动位置。

## 7. 我的名片背景图对比度（W5：task-17 第 1 部分）

**用户症状**：自定义背景图与 B 前端重叠、文字看不清（真机红圈）。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 7.1 | 有背景图时加统一遮罩（scrim/模糊/渐变/半透明底），头像/名字/三栏/铅笔按钮**清晰可读**（对比度达标：正文 ≥4.5、次要 ≥3，按实际测量/代码色值） | 两态渲染对照（有图/无图）+ 代码 file:line | ☐ |
| 7.2 | 无背景图保持纸面卡（不因加 scrim 变灰/失真） | 图 + 代码分支 | ☐ |
| 7.3 | 编辑/换背景/头像等功能未回退 | 代码抽验 + 测试 | ☐ |

**涉及文件**：`lib/widgets/profile_name_card.dart`、`lib/screens/profile/profile_home.dart`、test/profile_*、图。**当前 WIP 已见**：profile_name_card +30、profile_home +30 → ◐。

## 8. 关于三入口 + 首启开屏公告（W5：task-17 第 2 部分）

**用户症状**：我的底部要新增「关于软件」三入口（软件声明/特色/思想，含真实文献链接），且首次下载初始化作为开屏公告；另要「开源许可」入口。

| # | 可勾选判据 | 证据要求 | 状态 |
|---|---|---|---|
| 8.1 | 三入口（软件声明/软件特色/软件思想）在「我的→关于与更新」可见可点 | 渲染 + 代码 file:line | ☐ |
| 8.2 | 内容页 Markdown **可读**（标题/列表/引用/链接排版正常），内容来自 `assets/about/*.md` 且**与 pubspec assets 声明一致**（`assets/about/` 已声明） | 图 + 文件实读 + pubspec 对照 | ☐ |
| 8.3 | 文内**外链可点开**（真实文献链接，launchExternalUrl） | 代码 + 抽验/测试 | ☐ |
| 8.4 | 内容**真实非占位**：声明含版权/免责/使用范围；特色写技术架构/定位；思想＝用户原文+真实文献引用（抽样核对文献链接非编造） | 读 md + 抽查链接可达性（网络允许时） | ☐ |
| 8.5 | **首启开屏公告只弹一次**（首弹/二不弹测试，Hive 标记如 `about_notice_seen_v1`）；公告含三块入口/摘要+「我已阅读并继续」；可重看 | 测试 + 渲染 ×2（首弹/我的入口重看） | ☐ |
| 8.6 | 公告不喧宾夺主（B 语言、有版本号）；「开源许可」入口存在且列真实依赖许可 | 图 + 代码 + 内容核对 | ☐ |
| 8.7 | 未改 Lead 写的内容文件（只读引用）；assets 只增不改既有；**不引入新依赖**（已核：`pubspec` 仅 +1 行 = `assets/about/` 声明，无 dependency 变更；`flutter_markdown` 为库内已有依赖，需在交付时确认未新增） | diff + pubspec 核对 | ☐ |

**涉及文件**：`lib/screens/profile/about_screen.dart`、`about_doc_screen.dart`、`about_notice_screen.dart`（新）、`lib/services/about_content.dart`、`about_notice.dart`（新）、`lib/widgets/about_notice_gate.dart`（新）、`lib/app.dart`（gate 接线）、`assets/about/*.md`、`test/profile_about_test.dart`（新）、图。**当前 WIP 已见**：以上新文件均已存在（12:05-12:13）、`pubspec.yaml +1`、`app.dart +11` → ◐（需核 pubspec 新增行是否 = 已有依赖声明/assets，并非新依赖）。

### 7.9 W5 名片复核结论（2026-11-07 14:0x）

- ✅ **有背景图加 scrim 后文字清晰**：`profile_name_card.dart:157` 纸面渐变 scrim（上 92% → 中 84% → 下 94% 纸色，照片仍看得出是照片）；图 `assist-mine-impl-namecard-photo.png` 实看：背景图存在但被纸色压到很淡，头像/「我的名片」眉标/名字/三栏「60 生词 / 未测·去测 / —」全部清晰可读 ✓。
- ✅ **无背景图保持纸面卡**：`namecard-plain.png` 实看=白纸面卡 + 顶部 3px 砖红条 + 眉标 + 铅笔 + 三栏，无 scrim 变灰失真 ✓。
- ✅ 编辑/换头像入口未回退（右上砖红铅笔仍在；profile_pages_test 14/14 含名片页）。
- P3（权衡）：scrim 92~94% 偏重 → 背景图"几乎只是纹理"，用户若希望背景可见可考虑降到 ~85% 或加"显示强度"设置（非必须）。
- ⚠️ 交付物同步：`namecard-plain/photo` 两张图只在 `build/ui_real`（13:52），docs 尚未同步（Lead 已说明稍后同步）。

### 8.9 W5 关于/开屏复核结论（2026-11-07 14:0x）

- ✅ 三入口：`about_screen.dart` 01 关于软件 = 软件声明/软件特色/软件思想/开屏公告（四行，图 `assist-mine-impl-about.png` 实看 ✓，行尾箭头可点）+ 04 关于这份软件里「开源许可」(`:190`，`showLicensePage` :45) ✓。
- ✅ 内容页 Markdown 可读：`about_doc_screen.dart` 用 `flutter_markdown`（已有依赖 ^0.7.7+1，**非本轮新增**）+ 自定义纸面样式；图 `assist-mine-impl-about-doc.png` 实看标题/引用块/段落排版正常；外链 `onTapLink → launchExternalUrl`（:57/:131）✓；内容真实非占位（`assets/about/*.md` 共 ~25KB，与 `about_content.dart:17/23/29` 引用名一致；软件思想含《现代汉语》等真实引用）✓。
- ✅ 首启开屏公告**只弹一次**：`about_notice.dart` 独立 key `about_notice_seen_v1`；`profile_about_test.dart:61` 测试「首次该弹；markSeen 后不再弹；reset 后恢复（只弹一次的证据）」通过；`:72` 文档元数据/版本 v2.28.0 测试通过（**8/8**）。
- ✅ 公告页（图 `assist-mine-impl-about-notice.png` 13:52 build）：WELCOME·首次使用 + v2.28.0 + 三份说明摘要 + 「点『我已阅读并继续』后不再自动弹出；随时可在我的→关于与更新重看」+ 砖红主行动 ✓；`about_notice_gate.dart` 首帧后检查、只弹一次（app.dart:62 已接）✓。
- ✅ assets 声明一致：`pubspec.yaml` 增 `assets/about/` 一行（无新依赖；版本 2.28.0+93）；`git diff` 无 DB 结构变更。
- **P2（已修复并关闭，2026-11-07 14:2x 复检）**：公告摘要卡曾把 Markdown **表格原文**显示出来；`about_content.dart:94-99 summaryOf()` 现在跳过含 `|` 的行（覆盖 `--- | ---` 分隔行）、跳过 ```/![ /<!--；`:100` 跳过含 `**`/`` ` ``/`](` 的残留行；`_plain()` 兜底删 `|`/`[..]`；`test/profile_about_render_test.dart:156-174` 同步同一规则。新图 `assist-mine-impl-about-notice.png`（14:14）三块摘要为**干净中文，无 `|`、无 `---`、无 Markdown 符号**（read_image 实看）✓。复检测试 `profile_about_test 8/8 + profile_about_render_test 5/5 + profile_pages_test 14/14` = **+27 passed**；`docs/ASSISTANT-MINE-IMPLEMENT.md §10.7` 已记录根因/修法/验证。
- P3：`about-doc` 页标题重复三级（AppBar「软件思想」+ kicker「谈谈语言学习的本质」+ 大标题「软件思想」+ md 首行 H1「软件思想」）→ 建议 md 去掉首个 H1 或页面不加大标题；W5 4 张图（about-notice/about-doc/namecard×2）待在 docs 同步。

---

## 9. 结论（终版，2026-11-07 14:1x）

> 每条 = ☑/✗ + 证据（file:line / 图 / 测试数字）；P0 = 退回项。

### 9.1 八条判定

| # | 条目 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 材料中心搜索质量 | **☑ 通过** | 检索词纯函数+3 层过滤+真题分级+理由阈值全部落地；测试 58 passed；图 7 张（含 form/filtered）；P3×2 可选（「其他」孤行/notes 两轮各报一次被截断） |
| 2 | 阅读器空间利用率 | **☑ 通过** | 正文 318→354px（+11.3%），竖轨 3px overlay 不挤压；保持 3px + 轨道对比度 1.45/1.42/1.65（旧 1.23）+ 填充对比 3.5/3.6/3.0；before/after 实图（同段 5→4 行、同屏多一段）；测试 15+16 passed；C 特征无回退 |
| 3 | 书架 3D 横档 | **☑ 通过** | 初始态无抽出封面（Key 断言+图）；点书脊抽出浮在书架上方不压书脊、再点收回；滑动只滚书脊；测试 +2 passed；图 3 张 |
| 4 | 自由搜 UI / AI 保底 | **☑ 通过** | 输入框不裁字、筛选默认收起+搜索后自动收起；空态真实原因；AI 改写独立卡在结果下方（有原文优先、不自动替换）+ 非原文/来源/字数实数；测试 12+21 passed；图 5 张 |
| 5 | 封面懒加载 | **☑ 通过** | 有图/无图两态；同 URL 一次、失败静默、无假图；公版书零网络；书架/我的同口径；测试 21 passed；两态对照图 |
| 6 | 输出四项 | **☑ 通过** | 四阶卡 Expanded/Flexible 不裁；CET-6→「六级写作评分标准」+ 5 维中文；rubric seed INSERT OR IGNORE 老库补种 0 迁移；答题卡可任意跳题；草稿 Hive + 首页「继续上次练习」；测试 10+12 passed；图 10 张 |
| 7 | 我的名片 scrim | **☑ 通过** | 有背景图加纸色 scrim（92/84/94）文字清晰；无图保持纸面卡；两态图；profile 14/14；P3=scrim 偏重背景图可见度低 |
| 8 | 关于三入口/开屏 | **☑ 通过（附 1 条 P2）** | 三入口+开源许可+Markdown 内容真实（25KB md，与 assets 声明一致）+外链可开；公告只弹一次有测试（8/8）+可重看；**P2：公告摘要卡显示 Markdown 表格原文（首启观感 bug，建议打包前修）**；P3=doc 标题三级重复 |

### 9.2 通用闸门

| 闸门 | 结论 | 证据 |
|---|---|---|
| G1 三重证据 | ☑ | 本文每条均 file:line + 图 + 测试数字 |
| G2 analyze | ☑ | 全库 `lockrun analyze --no-pub lib` = **0 error / 0 warning / 7 条存量 info**（process_chat×5、ai_article_section×1、article_reader×1，均非本轮文件） |
| G3 测试 | ☑ | 我独立分批跑：W1a 58 + W3 15(+render 16) + W1b 54 + W2 2 + W4 22 + W5 22 + 回归渲染 24 = **213 passed**；详见 9.3 |
| G4 占位/假数据 | ☑ | 改动的 6 条线生产代码 `TODO/FIXME/占位/后续再做` 仅命中注释性描述（"占位""不占位"），无 backlog 标记、无写死假数据（渲染 fixture 除外） |
| G5 跨作用域 | ☑（附记录） | 已记录：`lib/app.dart`（+11，AboutNoticeGate 接线，W5 计划写作用域未列 → 集成必需，请 Lead 确认记录）、`pubspec.yaml`（+1 assets/about、版本 2.28.0+93，无新依赖）；`word_action_sheet.dart`（v2.27.0 已批准例外，未再改）。其余均在各线写作用域内 |
| G6 逐屏图 | ☑ | W1a 7、W3 17、W1b 17、W2 3、W4 10、W5 5 = **59 张全部已同步 docs/ui-preview/real**（W5 5 张 14:14 补齐，G6 闭环） |
| G7 版本/依赖/DB | ☑ | `pubspec 2.28.0+93`；无新增依赖（`flutter_markdown ^0.7.7+1` 为已有）；`git diff database.dart` 无 ALTER/ensureColumn/dbVersion → **零迁移**；未 commit/push |
| G8 上一轮无回退 | ☑ | ① find 旧 AI 找材料页仍零活入口（本次未动）；② 频道分页/继续找更多/快照回归 24 passed；③ reader C 特征（零按钮/把手/刊头双线/三纸/只生词下划线/控制台 4 组不裁/进度≤99）图+测试复核无回退；④ output 来源行/等级筛选/`resolveExamType`/paper 口径未变；⑤ assist 12 内页+名片+空态未回退（profile 14/14）；⑥ 书架不再有假封面（W2 重新验证） |

### 9.3 我实跑的测试（独立复核，非转抄）

| 批次 | 文件 | 结果 |
|---|---|---|
| W1a | material_channel_query + need_search_reason + content_quality + material_discovery_batch | **+58 passed** |
| W3 | reader_c_layout + reader_c_widget + reader_c_paper（另 render 单独 16/16） | **+15 passed**（+16 render） |
| W1b | find_material_free_search + find_material_ai_rewrite + material_result_list | **+54 passed** |
| W2 | bookshelf_views | **+2 passed** |
| W4 | output_impl_render（10/10）+ practice_flow + output_draft | **+10 / +12 passed** |
| W5 | profile_about + profile_pages | **+22 passed**（8+14） |
| 回归 | find_material_render + material_channel_paging | **+24 passed** |
| 合计 | | **≈213 passed / 0 failed**（另 W3 render 16/16 单独确认） |

> 环境说明：首批合并跑时遇到过 2 次**环境抖动**（一次「墨夜(深色纸)」出图失败、一次 render `setUpAll` 失败），根因是当时 `.buildlock` 被上一轮被杀进程残留（锁目录存在但无 flutter/dart 进程），清理后单独/分批重跑全部通过；不是代码缺陷。建议最终闸门在干净环境再跑一次全量确认。

### 9.4 P0 / P2 / P3 汇总

- **P0（退回）：无。**
- **P2：已修复并复检关闭（0 待修）。** 公告摘要 Markdown 表格 → 已按 §8.9/§9.6 修复，新图 14:14 干净、复检测试 +27 passed。
- **P3（记录，可下轮）**：
  1. 频道「按形式」9 chips 中「其他」孤占第三行（缩 spacing/并排可选）；
  2. 频道过滤 notes 两轮各报一次且第二句被 `maxLines:2` 截断（建议合并总数）；
  3. W1a 两条小 nit 如上；
  4. `output-impl-answer-cet6.png` 未含题干（补图或注明滚动位）；
  5. about-doc 标题三级重复；
  6. 名片 scrim 偏重（背景图几乎不可见，可按用户口味降到 ~85%）；
  7. W5 4 张关于/名片图待在 docs/ui-preview 同步；
  8. 开屏动画/logo 属另一条设计线（用户未选定，不在本轮 8 条范围，已知）。

### 9.6 P2 复检记录（2026-11-07 14:2x，assistant-mine-design 修复后）

- 代码：`about_content.dart:94-99` 跳过含 `|` 行（含 `--- | ---`）、跳过 ```/![ /<!--；`:100` 跳过 `**`/`` ` ``/`](` 残留；`_plain()` 兜底删 `|`；`profile_about_render_test.dart:156-174` 渲染链路同步同规则（词条对得上，不会图与线上不一致）。
- 图：`docs/ui-preview/real/assist-mine-impl-about-notice.png`（14:14）**三块摘要均为干净中文句子**：声明「这是一个由个人独立开发的 Android 学习类 App，免费、非商业…」/ 特色「大多数语言 App 是『单点工具』…」/ 思想「本杂谈从『语言』本身的定义出发…」——**无 `|`、无 `---`、无 Markdown 符号** ✓。
- G6 闭环：W5 5 张图（about / about-notice / about-doc / namecard-plain / namecard-photo）14:14 已在 docs/ui-preview/real；about.png 新版含 01 四入口 + v2.28.0，开源许可入口在第二屏（已知 P3）。
- 回归实测：`profile_about_test + profile_about_render_test + profile_pages_test` → **+27 passed / 0 failed**（8+5+14）。
- 8 条回归点抽查（§1.0）：find 旧页仍零活入口（3 处引用全死链，新入口 3 处）；reader 无 AppBar/FAB、进度 clamp .99、生词 highlightWords、`reader_paper` 持久化键在；assist 12 内页 V4JellyAppBar（about/about_doc 也用了）；output 来源行 P0-1 仍在（flow:757/history:25）+ `examTypeOverride`（setup:331）+ `listExerciseSets(examType:)`；输入底部统一 `showDragHandle`（双横杠已消）；封面「有图才画图/errorBuilder 中性占位」/书架文字版式无假封面（§grid 注释与代码一致）——**无回退**。
- **最终放行结论：8 条 ☑、P0=0、P2 已关闭、G1–G8 全过；task-18 验收通过，可进全量闸门与打包。**（开屏/logo 属另一条设计线，Lead 将单独转「开屏专项」复核，不在本 8 条范围。）
