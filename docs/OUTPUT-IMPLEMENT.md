# 输出板块实施对照表（2026-11-06 夜 · A 纸面 + 入口 B 头图）

> 用户拍板：输出 = **A 纸面工作台（内页）+ 入口借 B 果冻头图**；
> 同时修 P0-1「练习材料没标来源/年份/套数」、P0-2「四六级混排」，
> 二期「拆四级/六级两个学习目标」已获用户同意（Lead 裁决：**零迁移**）。
>
> 本文是「不缺斤少两」的对照表：**设计条目 → 实现 file:line → 渲染图 / 测试证据**。
> 约束遵守：未 commit、未改 pubspec、未加依赖、未改 dbVersion、**未加任何数据库列**。

## 0. 一页结论

| 项 | 状态 | 证据 |
|---|---|---|
| 视觉 A 纸面（内页 7 屏） | 已落地 | §4 对照表 + 9 张 PNG |
| 入口借 B 果冻头图 | 已落地（渐变+两团光斑+白胶囊 CTA） | `output_home.dart` 头图 + `output-impl-home.png` |
| P0-1 来源缺失 | 已修（入口年份/套数 → 抽取 → 落库 → 三处展示） | §1 + `test/output_paper_meta_test.dart` |
| P0-2 四六级分桶 | 已修（筛选 + 统一映射 + 回填按钮） | §2 + §3 |
| M3 拆四级/六级目标 | 已落地（零迁移，读时展开） | §3 |
| M5 词池按等级切分 | 已落地（exam_vocab 的 exams 标签） | §5 |
| 测试 / analyze | 见 §6（收尾数字以最后一次运行为准） | — |

## 1. P0-1「来源缺失」：设计条目 → 实现

| # | 设计条目（docs/OUTPUT-REDESIGN-PLAN §一） | 实现 | 证据 |
|---|---|---|---|
| 1 | 纯函数从 URL/页面标题抽「YYYY年M月 + 第N套」，**只认命中不猜** | `lib/services/output_paper.dart:124` `parsePaperMeta`（中文年/月/汉字套数、`2023.12`、英文 `December 2023`/`Set 2`、全角数字、非法月份/套数丢弃） | 单测 28 例 |
| 2 | 多页来源按字段合并 | `output_paper.dart:216` `mergePaperMeta` | 单测 |
| 3 | `OutputSetSpec` 加 paper 字段 | `lib/services/output_composer.dart:305`（`paperYear/paperLabel/sourceSite` + `toJson/fromJson:329` 起，老 JSON 兼容） | 单测「JSON 往返」「老 JSON 不崩」 |
| 4 | 出题器接收年份/套数并**只从抓取页**认定卷面 | `output_composer.dart:1056` `composeFromExam`（新增 `setNo`；卷面身份由 `parsePaperMeta` 从 hit.title/URL/正文抬头抽取；用户选年只作检索条件） | 代码 + `output-impl-setup.png` |
| 5 | 入口补「年份/套数」选择 | `lib/screens/output/practice_setup_screen.dart:455` `_pickExamPaper`（不限 / 近 7 年 / 第 1~3 套） | 渲染图 `output-impl-setup.png` |
| 6 | `_saveSet` 写 `paper_year/paper_label`（**列已存在，0 迁移**） | `practice_setup_screen.dart:588` `_saveSet` | 代码（这两列建表见 `lib/services/database.dart` `exercise_sets.paper_year/paper_label`） |
| 7 | 统一来源行「等级 · 年份套数 · 来源站点 · 校对」 | `output_paper.dart:279` `examSourceLine` + `:313` `siteOfLicenseNote`（站点从 license_note 里的 URL 反推，**不加列**） | 单测 + 三张 PNG |
| 8 | 题库卡显示来源行 | `lib/screens/output/practice_history_screen.dart:323` `PaperRow`（meta = 来源行、meta2 = 来源类型/分区/日期） | `output-impl-history.png` |
| 9 | 答题页显示来源行 + 等级标签 | `lib/screens/output/practice_flow_screen.dart:230`（`sourceLine`）+ `:244` 起（纸面骨架，等级芯片在进度行右侧） | `output-impl-answer.png` |
| 10 | 历史题组重练也带来源/卷面 | `practice_history_screen.dart` `_open` → `OutputSetSpec(paperYear/paperLabel/sourceSite/licenseNote/verifyStatus)` | 代码 |
| 11 | 单题 `source_url` 入库需加列 → **不擅自迁移** | 本轮**未加列**：组级 `license_note` 已存全部抓取 URL，`siteOfLicenseNote` 反推站点；单题 URL 仍只在题目内存对象上（`OutputTaskSpec.sourceUrl`），需要入库时另提方案 | 本文 §7 风险 |
| 12 | **P2-1（QA）设置页等级筛选对「从材料出题」不生效** | `output_composer.dart` 新增纯函数 `resolveExamType({examGoals, examTypeOverride})`（筛优先、目标兜底）；`composeFromMaterial` 增 `examTypeOverride` 参数；`practice_setup_screen.dart` 材料出题传 `_effectiveExam`。单测：`test/output_paper_meta_test.dart` 的「resolveExamType · 入口等级筛选优先（P2-1）」证明筛 CET-6 后材料题组落 `cet6` | 单测 + 代码 |

**关键修复点（原根因）**：`practice_setup_screen.dart` 旧代码把 `paper_label` 硬编码成 `''`、`paper_year` 从不写；
检索结果的 `title/siteName/date` 被丢弃；`OutputSetSpec` 没有载体字段。现在四处全部补齐。

## 2. P0-2「四六级混排」：设计条目 → 实现

| # | 设计条目 | 实现 | 证据 |
|---|---|---|---|
| 1 | 题库页等级筛选「全部/CET-4/CET-6/考研/雅思」 | `practice_history_screen.dart:259` `PaperLevelTabs` + `_load` 传 `examType`（`DatabaseService.listExerciseSets(examType:)` 现成） | `output-impl-history.png` |
| 2 | 四阶设置页也能按等级出题 | `practice_setup_screen.dart:645` `PaperLevelTabs` + `_applyLevel`（切等级重载考纲词并驱动真题/来源） | `output-impl-setup.png` |
| 3 | 统一「目标 → 考试等级」映射（修中文落 none、泛化不压明确） | `output_composer.dart:826` `examTypeFromGoalIds` 改为与 `examTypeOfText` 同源；`['cet','kaoyan']→kaoyan` 与 `targetExamOf` 两趟语义一致 | 单测（`output_composer_test.dart` 已按新语义更新并注明） |
| 4 | 老数据回填按钮（显式、按标题/URL 关键词重判、不隐式迁移） | `lib/services/output_exam_backfill.dart:66` `backfillExerciseExamMeta`（幂等）；`DatabaseService.updateExerciseSetMeta`（`database.dart:2606`，只写现有 3 列）；题库顶栏 `_runBackfill`（`practice_history_screen.dart:76`，确认弹窗 + 报数） | 代码 + `output-impl-history.png` 顶栏按钮 |

## 3. M3「拆四级/六级目标」：零迁移方案（Lead 已裁决 (a)）

**三件事（按 Lead 要求写清）**

1. **旧「四六级」= 通用档，不是历史包袱。**
   目标目录保留 `id:'cet', label:'四六级'`（`lib/services/drill_catalog.dart:127`，排在四级/六级**之后**，
   `what` 写明"等于四级+六级两级一起练，想单独练选四级/六级"）；
   **已存 `LearnerModel.goals` 里的「四六级」一个字都不改**（不做启动迁移、不物理拆条）。
   读取时由 `examTypesForGoals()`（`lib/services/output_source.dart:599`）把「四六级」展开成
   `{cet4, cet6}` —— 筛选、来源匹配、词池选择都走这一层，所以老用户不重选也能"按四级/六级筛"。
2. **新「四级」「六级」= 明确档。**
   `drill_catalog.dart:93`（`id:'cet4', label:'四级'`）与 `:109`（`id:'cet6', label:'六级'`）；
   筛选/词池/出题按明确的 `cet4`/`cet6` 走：
   - 题库/设置筛选：`listExerciseSets(examType: 'cet4'|'cet6')`；
   - 词池：`OutputBank.wordsForLevel('cet4'|'cet6')`（§5）；
   - 目标→等级：`examTypeFromGoalIds` 优先取明确档。
3. **统计/推荐口径（不会重复计数）。**
   - **展开只发生在"筛选/匹配"这一层**（`examTypesForGoals`），不写回任何表；
   - 统计（快照/周报/能力趋势）读的是**真实存下来的 `goals` 标签**与 `exercise_sets/attempts` 行：
     一条题组=一行，展开不会让同一篇真题在统计里出现两次；
   - 用户同时勾「四级 + 六级」时，筛选看的是**并集**，但题组条数/练习次数仍是按行计数，不受并集影响；
   - 推荐（`OutputBank.recommendedSources` / `OutputPracticeSource.matches`）用 goals 字符串匹配，
     新标签「四级」「六级」已加入各来源的 `matchesGoals`，老「四六级」同时命中两类来源。
   - **设置页呈现（最终实现，Lead 授权的 1 处输入线文案）**：设置页
     （`lib/screens/input/learner_preferences_screen.dart` 的 `_goalOptions`）由 `DrillCatalog.goals` 驱动，
     三个选项自动出现。为避免"以为要选两次"：
     ① 目录顺序 **四级 / 六级 在前、旧「四六级」在后**（`drill_catalog.dart:93/109/127`）；
     ② 旧「四六级」的 `what` 写明「通用档：等于『四级 + 六级』两级一起练；想单独练某一级就选上面的四级或六级」；
     ③ 目标卡片下方**新增一行说明**（授权例外，仅此 1 行、不动其它逻辑）：
     「『四六级』= 四级 + 六级 通用档；想单独练某一级，请选『四级』或『六级』。」

## 4. 视觉 A（纸面工作台）：设计条目 → 实现 → 渲染图

**共用纸面件**（不新造组件体系，全部走 `V4Skin/AppFont/Gap/Radii`）：
`lib/screens/output/widgets/paper_kit.dart`
- 纸面令牌：`:39 PaperPalette`（暖纸底 `#F5F3EC` / 暖灰细边 `#E2DDD0` / 近黑墨 `#1D1B17` /
  唯一暖点缀砖红 `#9A452C` / 四组暖纸档位色）；`:79 paperThemeOf` 一次覆写
  `V4Skin + ColorScheme + 按钮/输入框主题`（所以页面里的 `AppCard`/旧按钮也一起变纸面，
  不会残留果冻紫）；`:169 PaperSkin` 包裹层；`:184 paperAppBar` 给仍用 AppBar 的内页过渡。
- 结构件：`:213 PaperScaffold`、`:257 PaperTopBar`、`:381 PaperTitle`、`:436 PaperLevelTabs`、
  `:491 PaperSectionHead`、`:551 PaperCard`、`:599 PaperRow`、`:687 PaperFlatRow`、
  `:769 PaperSourceLine`、`:830 PaperMetaChip`、`:867 PaperPillButton`、
  `:931 PaperBottomAction`、`:951 PaperProgressLine`、`:979 PaperEmpty`。
- **关键修正（Lead 00:38 复核后返工）**：纸面主题改成在 `PaperScaffold` 内部整体套 `Theme`，
  并且主行动/选中胶囊 = **墨色实心（无渐变）**、按钮与输入框主题重新生成
  （原先只改 `V4Skin`，`AppTheme` 捕获的果冻主色会漏紫）；列表底部留 `120` 内边距，
  底部固定 CTA 不再压住最后一张卡。

| 屏 | 实现要点 | 完成度 | 渲染图 |
|---|---|---|---|
| 输出首页（入口） | B 果冻头图：渐变 + 两团光斑 + 白胶囊 CTA（`output_home.dart` 头图 + `_heroBlob`）；四阶改纸面清单（编号 01~04 + 果冻图标块 + 进度，`widgets/output_tier_card.dart`）；区块头用 `PaperSectionHead`；今日建议卡去掉 AppStagger 占位（QA P3） | 逐控件重排 | `output-impl-home.png` |
| 练习中心弹层 | 生产弹层内容改纸面件（`PaperRow`，替换旧 ListTile）；标题区保留 | 逐控件重排 | `output-impl-practice-center.png` |
| 四阶设置 | 纸面：`PaperTitle` + 等级筛选 + 编号区块（01 按目标练 / 02 从材料出题）+ `PaperBottomAction` 唯一主行动；逐卡换 `PaperCard`/`PaperRow`；题型/年份套数弹层也用 `PaperRow` | 逐控件重排 | `output-impl-setup.png` |
| 答题页 | 顶部细进度线 + 第 N/M 题 + 等级芯片；题干 `PaperCard`；作答纸面（无边框输入区 + 细线分区 + 拍照/相册）；rubric 预告卡；来源行；底部唯一「提交批改」（结果态变「再写一遍 / 下一题」） | 逐控件重排 | `output-impl-answer.png` |
| 批改结果 | 分数环白卡（总分 + 档位 + 折算档位）+ 编号区块（01 维度分 / 02 需要改的地方 / 03 参考改写）+ 问题条改"中性面 + 左侧主色细条"（去掉脏红大块） | 逐控件重排 | `output-impl-result.png` |
| 写译工作台 | **首屏编辑态逐控件重排**：`PaperTitle` + 编号区块 01 材料类型 / 02 练习类型（新 `PaperSegmented`：细边 + 选中墨色，替换旧 M3 药丸）/ 03 手写稿（纸面卡：虚线感空态 + 相册/拍照 + 次级"先转电子档" + 主行动"直接批改手写图"）/ 04 电子档（白纸卡包输入区，消除中部大空白）；底部"AI 批改"按状态让位（同一屏只留一个主行动）；批改设置弹层套 `paperThemeOf`（ChoiceChip 不再落果冻色） | 首屏逐控件重排；结果/加载态为主题覆写（沿用既有结构） | `output-impl-write.png` |
| 题库 | 纸面列表 + 等级筛选 + 来源行 + 顶栏「重建题源标签」回填按钮 + 纸面空态 | 逐控件重排 | `output-impl-history.png` |
| 旧计划页（练习中心） | 首屏 5 个**编号区块**（01 怎么练 / 02 目标需求 / 03 当前水平 / 04 进度追踪 / 05 开始练）+ 纸面顶栏；旧卡片/开关/按钮经 `paperThemeOf` 一并纸面化；**行为一行未动** | 首屏结构重排 + 主题覆写（内部为共享组件，故不再逐控件替换） | `output-impl-plan.png` |

## 5. M5 内置词池按等级切分

| 条目 | 实现 | 证据 |
|---|---|---|
| 四级/六级词池分桶 | `lib/services/output_bank.dart:630` `wordsForLevel(examId)`（读 `assets/data/exam_vocab.json` 的 `exams` 多标签）+ `:644 cet6WordCount`；来源卡 `:665 id:'cet6_words'`、`:656` 起 `cet4_words` 标题改「四级高频词」 | `output-impl-setup.png`（按等级出题）+ 代码 |
| 词表未加载时降级 | `_practiceFromSource`（`practice_setup_screen.dart`）word 分支：词表空 → 回落内置四六级精选池（点了一定有词） | 代码 |
| 作文题池 | 保持单一「四六级作文题」池（题目等级中性、rubric 同一套 `cet4_writing` 维度）；**已知限制**：暂未新增 `cet6_writing` rubric（rubric seed 属数据库初始化，本轮不动 dbVersion） | 本文 §7 |

## 6. 测试与 analyze（命令 + 最后一次数字）

```bash
cd /d/readflow
# 目录级 analyze(收尾必须 0 error / 0 warning)
bash tool/lockrun.sh analyze --no-pub lib/screens/output lib/screens/writing lib/services
# P0-1 单测
bash tool/lockrun.sh test test/output_paper_meta_test.dart test/output_composer_test.dart --no-pub
# 输出相关回归
bash tool/lockrun.sh test test/output_*.dart test/practice_*.dart test/drill_*.dart test/cloze_practice_test.dart test/sentence_practice_test.dart test/write_review_rubric_test.dart test/band_suggestion_ui_test.dart test/learner_snapshot_output_test.dart --no-pub
# 8 张逐屏渲染（+1 张 setup 滚到底验证图）
bash tool/lockrun.sh test test/output_impl_render_test.dart --no-pub
```

- 新增单测：`test/output_paper_meta_test.dart`（29 例：抽取/不猜/合并/站点/映射/JSON/query/`resolveExamType` P2-1）。
- 更新单测：`test/output_composer_test.dart`（`examTypeFromGoalIds` 按新语义更新，注明原因）。
- 回归：`practice_flow_test.dart` 保持绿（`第 1/1 题` 文案、360 宽不溢出、纸面卡里的 ListTile 不触发 ink 断言）。
- **最终数字（2026-11-07 01:55 收尾版）**：QA 全量实测 **264 passed**；本主题最终定向回归 **249 passed**
  （16 个输出相关测试文件）；`test/output_impl_render_test.dart` **9/9 passed**；
  目录级 analyze（output + writing + services + input/learner_preferences + 渲染测试）
  = **0 error / 0 warning / 1 条存量 info**（`article_reader.dart:319`，非本轮新增）。

## 7. 未做 / 已知限制 / 风险

0. **命名裁决（Lead 已批准并记录）**：纸面件用 `paper_kit.dart` + `Paper*` 前缀，不并入全局 `v4_kit`。
   理由：纸面语言只服务输出板块内页，放 `lib/screens/output/widgets/` 是**局部**件，
   `Paper*` 比 `V4*` 更准确（不是第四个版本的全局组件），也不污染其他三条线正在改的全局文件。
1. **单题 `source_url` 未入库**：`exercise_items` 无该列；本轮不加列（纪律）。组级 `license_note` 已保存全部抓取 URL，答题页/题库/历史都能显示"来源站点 + 年份套数"。若产品要求"点开原网页"直达单题，需加 1 列 + 迁移（另提方案，等用户批准）。
2. **六级 rubric**：`rubrics` seed 只有 `cet4_writing/cet4_translation/back_translation/summary`；六级目前复用同一套维度（写作/翻译通用四维），若需六级专属档位需改 rubric seed（属 DB 初始化，记二期）。
3. **写译工作台**：**首屏编辑态已逐控件重排**（编号区块 01~04 + `PaperSegmented` + 纸面卡 + 状态化唯一主行动）；批改结果/加载/错误态仍是"`paperThemeOf` 主题覆写 + 既有结构"（视觉已纸面，未逐控件重排），理由：那几态是结果展示，信息结构本身没变。
4. **练习中心/旧计划页**：首屏已按 5 个编号区块重排 + 纸面顶栏；内部控件是共享组件（`AppCard`/`Switch`/按钮），经 `paperThemeOf` 统一纸面化，**未逐个替换为 `Paper*`** —— 因为它同时被"练习中心弹层"复用，逐控件替换会牵动两条入口。
5. **动手边界**：`lib/screens/input/**` 只改了 Lead 授权的 1 行文案（目标说明），其余未动；`profile/**`、`tutor/**`、全局 `widgets/**` 一行未改；`write_review_screen.dart` 保留了另一位 agent 的"双横杠修复"改动。
6. 渲染图是**假数据 + 生产组件**；真机首帧仍需用户验收（本轮不出包）。

## 8. W4 · 真机反馈 4 条（2026-11-07 第二轮）

| # | 用户反馈 | 根因 | 修法（file:line） | 证据 |
|---|---|---|---|---|
| 1 | 四阶卡副标题被卡片底边裁字 | 首页四阶用固定 `childAspectRatio: 1.28`，卡片高度不够两行副标题 + 进度行 | `output_home.dart` 四阶网格 `childAspectRatio: 1.02`（高度 171→168 逻辑像素以上的呼吸）；`widgets/output_tier_card.dart` 内容在固定高度内用 `Expanded + Flexible`，副标题保持 2 行不裁 | `output-impl-home.png` |
| 2 | 练 CET-6 却显示 `cet4_writing` 评分标准 | ① rubric 选取只按题目存的 id，材料/作文链路一律写死 `cet4_*`；② rubrics 表只有四级 seed；③ UI 直接 `Text(rubric.id)` | ① `output_rubric.dart`：新增 `cet6_writing`/`cet6_translation` 内置 rubric + `rubricIdFor()`（按 examType 选）+ `resolveFor()`（老数据 cet4_* → cet6_* 纠正）+ `displayNameOf()`（中文名）；② `database.dart:_builtinRubricRows` 幂等补六级 seed（`INSERT OR IGNORE`，开库自检时补，老库也补）；③ 出题链路改用 `rubricIdFor`（`output_composer.parseExamWritingTasks`/`composeFromMaterial`、`output_bank.buildEssaySet(examType:)`）；④ 答题页预览显示中文名（`practice_flow_screen._buildRubricPreview`） | `output-impl-answer-cet6.png` + `test/output_rubric_cet6_test.dart` |
| 3 | 练习必须按顺序做、不能跳题 | 答题页只有"当前题"，没有题目导航/整组状态 | `practice_flow_screen.dart`：每题草稿与批改结果按题号存（`_texts`/`_scored`）+ 顶部与底栏「答题卡」入口 + 任意跳题 + 上一题/下一题 + 完成前校验未批改数（可继续作答或仍然完成） | `output-impl-answer.png`（第 1/3 题 + 答题卡）+ `practice_flow_test.dart` 跳题用例 |
| 4 | 练习退出不留存、下次重新找 | 题组其实已落库，但**没记录停在第几题/每题草稿**，首页也无恢复入口 | 新增 `lib/services/output_draft.dart`：`OutputDraftStore`（Hive 单行 JSON：setId/题号/每题文本，不加表不加列）、`setSpecFromExerciseRow`（与题库重练共用还原口径）、`loadResumablePractice`、`loadScoredByIndex`（已批改从 `output_attempts.score_json` 还原）；练习器退出/跳题/提交时写草稿、全部批改后清草稿；输出首页新增「继续上次练习」卡片（`output_home._resumable`） | `output-impl-home.png`（继续上次练习卡）+ `test/output_draft_test.dart` + `practice_flow_test.dart` 恢复用例 |

> 说明：草稿只存**未提交的作答文本 + 当前位置**（客户端状态，Hive）；已批改结果仍以
> `output_attempts` 为唯一权威数据源，不落第二份分数。全程**未加数据库列/表、未改 dbVersion**。

## 9. 渲染清单（`docs/ui-preview/real/`，同名也写 `build/ui_real/`）

| 文件 | 屏 |
|---|---|
| `output-impl-home.png` | 输出首页（B 头图 + 四阶纸面） |
| `output-impl-practice-center.png` | 练习中心弹层 |
| `output-impl-setup.png` | 四阶设置（含等级筛选/来源/年份套数入口） |
| `output-impl-setup-bottom.png` | 四阶设置**滚到底**（验证底部固定 CTA 不遮挡最后一张材料卡） |
| `output-impl-answer.png` | 答题页（来源行 + 等级徽标 + rubric 预告 + 白纸作答区；W4 起含答题卡跳题） |
| `output-impl-answer-cet6.png` | 答题页滚到 rubric 预告：证明显示「六级写作评分标准」而不是 `cet4_writing` |
| `output-impl-result.png` | 批改结果（分数环 + 编号区块 + 低干扰问题条） |
| `output-impl-history.png` | 题库（等级筛选 + 来源行 + 回填按钮） |
| `output-impl-plan.png` | 旧计划页（练习中心） |
| `output-impl-write.png` | 写译工作台 |

> 逐张自检结论（2026-11-07 01:20）：9 张全部为**暖纸底 + 细边浅卡 + 编号区块 + 墨色唯一主行动**；
> 内页无果冻紫残留（`paperThemeOf` 覆写 `V4Skin/ColorScheme/按钮/输入框/Chip` 主题）；
> 入口屏 `output-impl-home.png` 保留 B 果冻头图（渐变 + 光斑 + 白胶囊 CTA），其余屏无渐变/无彩色主按钮；
> setup 滚到底图证明 CTA 不压最后一项；plan / write 为真实内容（199KB / 127KB），非骨架/空态。
