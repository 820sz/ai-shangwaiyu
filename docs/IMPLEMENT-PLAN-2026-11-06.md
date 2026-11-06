# 选型后 · 实施总计划（2026-11-06 深夜用户拍板）

> 用户拍板结果+质量要求（原话要点）：
> 1. **阅读器走 C 方案**，但把 B 方案里「纸张三色可选」搬过来；
> 2. **找材料走 A 方案**；其余按推荐（助理/我的 = B 主语言 + A 数据内页；输出 = A 内页 + 入口借 B 头图）；
> 3. **不单独打修复包**，整个软件做完顺带解决；
> 4. 输出二期**拆四级/六级两个目标：同意**；
> 5. 核心警告：「上一个对话预览画饼做得很好，实际产出要么缺斤少两、要么 bug 一堆」——本轮**质量与实现度优先**。

## 0. 「不缺斤少两」的硬定义（每个主题都必须过）

1. **设计文档逐项落地**：设计稿里出现的每个屏、每个区块、每个数值都要有实现；
   交付时必须附 `docs/<主题>-IMPLEMENT.md` 的**对照表**：设计条目 → 实现 file:line → 渲染图文件。
   **禁止 TODO / 占位 / "后续再做" / 假数据写死**。
2. **真实渲染逐屏**：不是一张代表图，而是把该主题的**每个屏**都渲染出来自检
   （390×844 @3x，真字体+真图标；无网络时用假数据，但布局与生产组件一致）。
3. **接线真实**：所有按钮/入口/返回/持久化都真跑通；不许出现"点了没反应/页面是静态图"。
4. **测试**：每个交互补 widget test 或纯函数单测；改动后跑定向测试 + `flutter analyze --no-pub lib`
   必须 **0 error / 0 warning**（存量 info 不算）；修复不得回归旧测试。
5. **QA 只读复核**：qa-verify 拿设计文档逐条打勾，任何缺项/假实现记 P0 退回，修完再验。

## 1. 工程纪律（多 agent 并行）

### 1.1 文件所有权（写作用域，互不重叠）

| 主题/agent | 写作用域 |
|---|---|
| 阅读器 | `lib/screens/input/material_reader_screen.dart`、`lib/widgets/reader_*.dart`、`lib/services/reader_settings.dart`、`test/reader_*`、`docs/ui-preview/real/reader-c-*.png`、`docs/READER-C-IMPLEMENT.md` |
| 找材料 | `lib/screens/input/find_material_screen.dart`/`free_search_screen.dart`/`need_search_screen.dart`、`lib/widgets/material_result_list.dart`、`lib/services/find_need_context.dart`、`material_center_screen.dart`/`material_hub_home_view.dart`/`material_taxonomy.dart` 必要接线、`material_channel_screen.dart`（**只允许抽结果列表，不许改行为**）、`test/find_material_*`/`test/material_result_list_test.dart`、`docs/FIND-MATERIAL-IMPLEMENT.md` |
| 输出 | `lib/screens/output/**`、`lib/services/output_*.dart`、`lib/services/drill_*.dart`、`lib/services/exam_*.dart`、`lib/services/practice_*.dart`、`lib/services/database.dart` 中 **仅** exercise_sets/paper 相关读写、`lib/screens/writing/**`、`test/output_*`/`test/exercise_*`/`test/practice_*`、`docs/OUTPUT-IMPLEMENT.md` |
| 助理/我的 | `lib/screens/tutor/**`、`lib/screens/profile/**`、`lib/services/tutor_*.dart`、`lib/widgets/` 下**新增** tutor/profile 专用件、`test/tutor_*`/`test/profile_*`、`docs/ASSISTANT-MINE-IMPLEMENT.md` |
| Lead | 全局组件（`lib/widgets/design_kit.dart`/`v4_kit.dart`/`v4_theme.dart`/`design_tokens.dart`）、`lib/screens/input/material_channel_screen.dart` 公共结果件抽取、集成、全量测试、发版 |
| qa-verify | 只读 + `docs/QA-IMPLEMENT-<主题>.md` |

> 需要动别人文件时：先发消息给 Lead，由 Lead 决定并记录；禁止直接改。

### 1.2 flutter 命令串行（必须用锁）

```bash
cd /d/readflow
bash tool/lockrun.sh analyze --no-pub lib
bash tool/lockrun.sh test test/xxx_test.dart --no-pub
```
并发直接跑会静默失败（`failed to delete ... sqlite3.dll`）。**每个 agent 每次跑命令都用 lockrun.sh**。

### 1.3 提交与打包

- 本轮所有 agent **不 commit、不改 pubspec、不加依赖、不改 dbVersion**；改动由 Lead 统一集成后提交。
- 用户明确：不单独打修复包；全部主题做完 + 全量测试 + 用户确认后，Lead 打一个完整包。

## 2. 四个主题的任务卡（设计文档为准）

### 2.1 阅读器 = C 方案 + 纸张三色（设计：`docs/READER-REDESIGN-OPTIONS-2026-11-06.md` §4 + §3 纸张色卡）

**必须实现的清单**（缺一项即不合格）：
1. 冷灰纸底（#EEEFEA 系）+ 近黑/次要/极淡三档文字色 + 唯一强调砖红 #B23A2C；
2. 字阶：标题 28/1.1/w900/-0.8、栏目标签 9.5/1.3/+1.6、署名 10.5/1.4/+0.3、首段 20/1.82、其余正文 18/1.8、译文 13.5/1.8；刊头 2px+1px 双线；
3. **零常驻按钮**：底部只有 贴底 2px 进度线 + 42px 把手区（左 % / 中间 36×4 抓手 / 右「上滑工具」）；
4. 右侧悬浮 `%` 胶囊 + 96px 竖轨道（3px 宽砖红填充），正文右侧让位；
5. **上滑「阅读控制台」4 组**：进度卡（已读 + 第 N 段/共 M 段 + 34px 数字 + 继续阅读 + 3px 进度线）/ 学习（翻译、追问、收词 12 三块）/ 目录（3 行紧凑行，本节 %）/ 材料（字号与行距、模型与思考档、导出·听写·读完）；
6. **纸张三色可切换**（搬 B 的亮点）：纸白（冷灰白，默认）/ 米黄（暖纸）/ 墨夜（深色纸），设置里三个色卡 + 实时预览卡；三纸都要各自可读（对比度、译文底、选中态）；
7. **真实阅读进度 %**：ValueNotifier + 常驻组件（不 setState 整屏）、`_onScroll` 更新、落库 percent 改真实比例（未读完最多 99）、续读按 percent 跳；书架/材料中心显示同一个值；
8. 弹层/查词/设置/目录全部按 C 方案重排；翻译进度不再压正文（收进控制台/顶部细条）；
9. 保留并回归：翻译范围/保存位置/进度落盘/书架/收藏/追问/阅读设置/目录/丰富形式/长按选词/生词高亮/图片/PDF 兜底。

**验收**：`docs/READER-C-IMPLEMENT.md` 对照表 + 逐屏渲染（首屏/上滑控制台/纸张三色各一张/目录/设置/查词/翻译进行中）≥8 张 + 新 widget test（控制台上滑、纸色持久化、进度更新、底部零按钮）。

### 2.2 找材料 = A 方案（设计：`docs/FIND-MATERIAL-REDESIGN-2026-11-06.md` §2 方向 A + §3 共用规格）

1. 入口页「找材料」：34px 标题 + 两张等宽大卡（自由搜 / 按我的情况找）+ 最近搜过 chips + 上次结果卡（复用快照）；
2. **FreeSearchScreen**：搜索框 + 来源/类型/难度/场景筛选（全部真实可落地）+ OriginalSearch 执行 + 搜索过程折叠 + 结果；
3. **NeedSearchScreen**：4 行真实依据（难度档/目标/弱项/最近阅读）+ 为什么推这些（两级文案，没数据不显示数字）+ 按条件找 + 结果；
4. 两份结果页共用 `MaterialResultList`：与频道页一致（类型分组 / 每页 10 条 / 页码控件 / 有真封面才显示 / 文字版式 / 开始读/保存到我的/打开原文 / 继续找更多）；
5. 接线：材料中心「找材料」卡 + 顶部 tune 按钮 → 新入口页；旧 `MaterialBrowseScreen` 入口下线（频道页「去设置需求」除外，由 2.2 之外的另一项处理）；
6. 学习助理数据来源必须真实（§3.1 表，file:line 可核对），空数据降级为「待测」；
7. 快照按 `free:<关键词>` / `need:all` 复用现有 store，不新增表/依赖。

**验收**：对照表 + 渲染（入口/自由搜空态/自由搜结果/按需找依据面板/按需找结果/无封面卡/空态）≥7 张 + 单测（FindNeedContext 降级 + 筛选/分页纯函数）+ 回归频道页测试。

### 2.3 助理 / 我的 = B 主语言 + A 数据内页（设计：`docs/ASSISTANT-MINE-REDESIGN-2026-11-06.md`）

1. 助理首页、我的首页按 B「每日简报」重做（暖纸白/日期刊头/时间线/引文/`TutorBriefing.build` 纯本地文案生成器 + 单测）；
2. 数据内页（统计/错误档案/复盘等）用 A 诊断台排版（KPI 带/五维细条/环），复用现成 `SparkBars/RadialGauge/StudyCalendar`；
3. **12 个裸 AppBar 内页全部换 `V4JellyAppBar`**（清单见设计文档 §1.2），逐屏核对；
4. 助理补**任务详情页**与**复盘页**（现在是底部弹层/页内卡，用户"点进去"无页可点）；
5. 我的补写译记录入口（服务/页面已有）；
6. 深色/360dp：至少做一次浅色真机比例渲染；深色允许二期，但**不能因此少做功能**。

**验收**：对照表 + 渲染（助理首页/任务详情/复盘/我的首页/统计/周报/错误档案/学习偏好/API设置/写译记录/备份/关于）≥12 张 + 单测（TutorBriefing + 空态）+ 12 内页 AppBar 逐项勾选。

### 2.4 输出板块（设计：`docs/OUTPUT-REDESIGN-PLAN-2026-11-06.md`）

**视觉（A 纸面工作台 + 入口借 B 头图）**：
1. 四阶设置页重做（纸面清单/编号区块/扁平等级胶囊/来源标注/唯一主行动）；
2. 答题页重做（来源行 + 等级标签 + rubric 预告 + 纸面题干/选项）；
3. 批改结果页重做（分数/维度/rubric 逐条/修改建议，低干扰）；
4. 写译工作台、题库、练习中心、旧计划页统一到 A 纸面；输出首页/练习中心入口借 B 果冻头图；
5. 视觉组件不新造一套，用 design_kit/v4_kit + 局部 A 纸面件。

**功能（P0-1 来源缺失）**：
6. 入口补年份/套数选择 → 出题器传 `year`；纯函数从 URL/页面标题抽「YYYY年M月 + 第N套」（只认命中不猜）；
7. `OutputSetSpec` 加 paper 字段；`_saveSet` 写 `paper_year`/`paper_label`（列已存在，0 迁移）；
8. 题库卡/答题页/历史还原统一一行「等级 · 年份套数 · 来源站点 · 校对」；
9. 单题 source_url 入库若需加列，先给方案不擅自迁移（列迁移需用户/Lead 确认）。

**功能（P0-2 四六级分桶）**：
10. 设置页/题库页加筛选行「全部/CET-4/CET-6/考研/雅思」（`listExerciseSets(examType:)` 已现成）；
11. 统一目标→等级映射（`targetExamOf` 为唯一口径；修 `examTypeFromGoalIds` 中文标签落 none 的 bug；真题链路不再一律 cet4）；
12. 老数据回填按钮（按标题/URL 关键词重判 exam_type，显式操作、不隐式迁移）；
13. **二期已获同意**：拆「四级」「六级」两个学习目标（`LearnerModel.goals` 语义扩展 + 旧"四六级"目标迁移兼容 + 相关 UI/统计/推荐跟随）；
14. 内置词池/作文池按等级切分（复用 `exam_vocab.json` 的 exams 多标签能力）。

**验收**：对照表 + 渲染（输出首页/练习中心/四阶设置/答题/批改/写译工作台/题库含筛选/计划页）≥8 张 + 单测（年份抽取纯函数/CET 映射/分桶过滤/目标迁移）+ analyze 0/0。

## 3. 并行与顺序

- 四个主题并行开工（4 个 impl agent）。**找材料依赖 Lead 先抽 `MaterialResultList`**（Lead 当天先做，
  抽完通知；找材料 agent 可先写 `FindNeedContext` + 三个新页骨架）。
- 每个主题完成 → 自己渲染 + 测试 → 交 Lead → Lead 集成跑 analyze/测试 → QA 复核 → 有缺项退回补。
- 四个主题都过 QA 后：全量 `flutter test`；用户确认；Lead 打完整包（版本号建议 2.27.0+92）。

## 4. 用户验收口径

- 真机截图验收（用户手机）；每主题附：渲染 PNG、对照表、测试数字、改动文件清单。
- 不拿"测试全绿"当效果；不以一张图代表整屏。

## 5. Lead 裁决记录（跨主题依赖，2026-11-06 23:3x）

| 编号 | 问题 | 裁决 |
|---|---|---|
| D1 | 阅读器 C 新令牌（#EEEFEA/#B23A2C/三档文字色）放哪 | **阅读器作用域内局部文件**（如 `lib/widgets/reader_tokens.dart`），不进全局 config/theme |
| D2 | 助理 B 暖色 flavor 放哪 | **tutor/profile 作用域局部常量**，不改 `v4_theme.dart` |
| D3 | 输出 A 的 4 个纸面件（V4LevelTabs/V4PaperRow/V4SourceLine/V4IndexHead） | **`lib/screens/output/output_kit.dart` 局部实现**，不进 `v4_kit.dart` |
| D4 | 找材料 MaterialResultList | 已落地，find 负责抽公共件 + 频道页零行为回归 |
| D5 | 纸张「米黄 / 墨夜」hex 未定义 | 实现自定 + 对照表登记；验收硬标准：正文对比度 ≥4.5:1、译文/次要 ≥3:1 |
| D6 | 找材料方向 A 的 `[历史]` 入口 | **必须实现**（轻量 sheet：读 MaterialPrefs 搜索历史、可回填、可清空），不许静默砍 |

另：P2-8「频道页去设置需求仍进旧 300 条页」由 Lead 在 `MaterialBrowseScreen` 增加
`settingsOnly` 模式（只显示需求编辑器+保存，保存后 pop(true)），频道页接线由 find 实施。

