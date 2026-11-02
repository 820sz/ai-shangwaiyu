# 输出模块 + 学习助理 · 现状侦察报告

> 侦察范围：`lib/screens/output/*`、`lib/screens/writing/*`、`lib/screens/tutor/*`、`lib/screens/input/learner_*`、`lib/services/{drill_*,tutor_engine,vocab_estimator,weekly_report,learner_*,material_source,deepseek_api,doubao_api,database}.dart`、`lib/models/{exercise,writing_log,learner_model}.dart`
> 代码基准：HEAD `eeea4b4`（2026-11-01 15:09）、`pubspec.yaml` version `2.13.0+71`、`AppConstants.dbVersion = 18`
> 方法：read / grep 通读代码；**未运行 App**（界面描述来自 Widget 树与注释，不是截图）；未查真机数据库（涉及"用户实际用了多少"的结论标 **未证实**）。
> 配套阅读：`docs/HANDOFF-FRONTEND-UPGRADE.md`（本轮升级的交接文档）。本报告只回答"现在是什么、地基有什么、缺什么"，方案只给最小可行形态，不代替设计。

---

## 0. 一句话结论

- **输出**：现有可称为"练习"的只有 **2 种客观小练习**（词汇拼写 / 中译英句子回译，题目全部从**生词本**里捞）+ **1 条 AI 自由写作批改**（写译批改，无题目、无 rubric）+ **1 个藏在文章阅读器里的 AI 抽句回译**（旧功能，判分粗、无对照）。四种页面骨架同构（纵向 AppCard 堆叠 + 顶部分段/卡片 + 一个大输入框 + 底部全宽按钮），练习结果**不出模块**（不回流能力画像 / 周报 / 助理 / 错误档案）。
- **助理**：现状分析 = **11 条本地规则诊断**（TutorEngine.diagnose，绝大多数是"行为债"而非能力项）；学习任务 = **同一套规则派生的 ≤4 条模板任务**（不可编辑、无自定义、无复盘）；需求询问 = **6 步单选访谈**（第 1 步目标单选，正是用户说的"四六级/兴趣阅读不能多选"）。底层已有相当扎实的**测量与数据资产**（词汇量 Yes/No 测试+伪词校准、FSRS 复习、阅读会话、错误标签、周报规则引擎），但这些资产**没有被组装成"更专业的现状分析"**。

---

# 第一部分 · 输出模块

## 1.1 现在"输出"tab 到底有哪几种练习

入口在底栏「练习」（`lib/widgets/bottom_nav.dart:18,64`）。`OutputHomeScreen`（`lib/screens/output/output_home.dart`）实际只有 4 个可用入口 + 1 个占位：

| # | 练习 | 入口（file:line） | 题目从哪来 | 判分方式 | 结果落哪 |
|---|---|---|---|---|---|
| 1 | **词汇拼写** | 输出首页卡 `output_home.dart:318-326`（`_drillTile` 417-551）→ `DrillScreen(mode: spelling)` | **软件内数据（生词本 `vocabulary`）**，不是 AI 生成、不是内置题库、不是用户导入题目。题面=`translation`（中文释义）+ 可选音标 | **客观**：忽略大小写的全等比较 `DrillPlanner.judgeSpelling`（`drill_planner.dart:1094-1099`）；错时给"第一个不同位置"逐字对照（`drill_screen.dart:409-423`） | `drill_logs`（`drill_screen.dart:543` → `database.dart:2764`）+ 错词立刻回复习队列（`drill_screen.dart:519-537`） |
| 2 | **翻译练习**（中→英句子回译） | 同上，`DrillMode.translation`（`drill_screen.dart:17-53`） | 同一份生词本里**带 `original_sentence` 的词条**；没有原句的词条直接出不了题（`drill_planner.dart:624-638`，空态说明 `drill_screen.dart:50-52`）。原句来自阅读器点词收藏 | **客观但很粗**：中文题面 vs 用户英文，按**词袋重合率 ≥ 0.5** 判对（`drill_planner.dart:1101-1109`）——不看语序、不看语法、不做词形还原，反馈给"词重合 6/9"（`drill_screen.dart:472-478`） | 同上 |
| 3 | **写译批改** | 输出首页「写」区 `output_home.dart:358-370` → `WriteReviewScreen` | **用户自由写作**（手写拍照 / 粘贴电子稿），**没有题目**；判分提示词可自定义（`writing_review_settings.dart:29-39`） | **AI 批改**：豆包 `reviewWriting`（`doubao_api.dart:839`）/ `reviewWritingImages`（:875），返回 `score/correction/issues/error_summary/summary`；分数是模型自由给的 0-100，**prompt 里没有任何评分细则/档位/维度权重** | 用户点保存才写 `writing_logs`（`write_review_screen.dart:394-423` → `database.dart:1478`；表结构 `database.dart:180-194`）；可收藏进 `bookmarks`（:429-459） |
| 4 | **回译练习（AI 抽句）** | **不在输出 tab**：只有「AI 生成的生词成文」文章阅读器里才有 → `lib/screens/output/article_reader.dart:241-289` 列表 + :311-329 生成按钮 → `ExerciseScreen` | **AI 生成**：从文章正文抽 5-8 个句子并给中文（`deepseek_api.dart:314-361`），存 `exercises` 表（`article_provider.dart:100-158`） | **客观但很粗**：逐句与参考英文原句词重合 ≥ 0.5（`utils/scoring.dart:3-20`）；旧数据没有英文参考时退化成**长度启发式**（:14-16） | `exercises.score`（`database.dart:1310-1325`）。**提交后页面只把输入框变灰 + AppBar 显示总分**（`exercise_screen.dart:138-156, 61-77`）——不展示逐句对错，也不展示参考答案 |
| 5 | **口语交流** | `output_home.dart:330-351` | — | — | 占位"开发中"，点开只有一段规划说明（:88-166） |

另外两个**在输入侧、但也算输出练习**的客观题型（用户既然说"输出=写"，这两个值得纳入重建视野）：

- **读后测验·完形/中译英**：`lib/screens/input/reading_quiz_screen.dart:7-17`，题目由 `services/reading_quiz.dart` **本地从材料正文生成**（不花钱、可复现），判分客观；结果写 `quiz_results`（:77-87）+ 错词写 `error_tags`（:89-93）+ 复习 lapse（:98-107）。这是全 App **唯一**把"练习结果→错误档案→复习"接通的链路。
- **听写**：`lib/screens/input/dictation_screen.dart`，客观判分，但**成绩不落库**——只把漏掉的词收进生词本并挂复习状态（:110-166）。

> 结论：用户说"只加入了我自己的想法'写单词和译练习'"是准确的。**目前没有任何"真题写作/段落翻译/教材回译"题型**，也没有题库概念：所有客观题都是"生词本镜像成题"，AI 只负责"抽句"和"整篇批改"两件事。

### 1.1.1 每种练习的"从哪来"必须说清的三件事

- **没有内置题库**：全库 grep `真题` 只命中"目标标签文案"（`drill_catalog.dart:92`）、"大纲主题词"（`drill_planner.dart:760-763`）、"题材选项"（`material_recommendation.dart:160`）——**没有任何真题内容**。
- **没有用户导入题目**：导入链路（`material_import.dart`）只导入**材料正文**；生词本里的"句子"来自阅读器点词自动带出。
- **AI 生成只有两处**：`generateBackTranslationExercise`（抽句，`deepseek_api.dart:314`）与写译批改（`doubao_api.dart:839/875`）。AI **不参与**拼写/翻译练习的出题与判分。

## 1.2 练习区 UI 有几种页面骨架（同质化在哪）

### 1.2.1 输出首页（`output_home.dart:168-388`）
从上到下：`SafeArea > ListView` → 大标题「练习」（:195）+ 副标题「用你生词本里的真实词与句出题」（:202）+ 右上「练习中心」→ **目标/水平大卡**（:217-306，旗帜图标 + "目标:四六级 + 兴趣阅读" + 三枚信息胶囊 + 一行说明）→ `AppSectionHeader「练」01`（:310-317）→ **2 张练习入口卡**（:318-326，每张=_drillTile：38×38 图标盒 + 标题 + 一行说明 + 内嵌"进度摘要"小方框 + 细进度条 + "今天 0/30 题" + "正确率 0%"）→ **口语占位卡**（:330-351，75% 透明度 + "开发中"角标）→ `AppSectionHeader「写」02`（:354-357）→ 两张 `AppActionTile`（写译批改 / 写译记录，:358-382）。

### 1.2.2 练习中心（`drill_plan_screen.dart:743-792`）
`AppBar「练习中心」` + 一个 `ListView`，自上而下 5 段、**每段都是 AppSectionTitle + AppCard 纵向堆叠**：
1. **怎么练**（:797-860）：3 张单选卡（跟计划走 / 今日练习包 / 自适应），每张=单选圆点+标题+一行说明；
2. **练什么**（:863-942）：目标卡（chips + 每个目标的"练什么"多行说明）；点开是底部弹层多选（:26-60，按 GoalTag 分组 FilterChip）；
3. **什么水平**（:945-1053）：等级大字 + "N 个生词在练" + 一句数据来源说明 + 用户补充说明框；
4. **进度追踪**（:1056-1268）：计划进度条 + 三个大数字（打卡天数/累计题数/正确率）+ 自绘 7 根趋势小柱（`_TrendBars` :1457+）；
5. **4 周练什么**（:1270-1345）：4 张周卡（本周高亮）+ **开始练**（:1348+）：只练到期开关 + 2 张开始卡。

### 1.2.3 答题页（拼写/翻译**共用同一套骨架**，`drill_screen.dart:747-951`）
`ListView` → ① 进度卡：`ProgressStageBar`（第 N/M 题 + 已用时 + 可退出，:708-719）→ ② 一行说明"按「目标」·进阶档 · 只练到期词组题"（:761-775）→ ③ **题面卡**：胶囊行（拼写/翻译 + 新词/学习中/已掌握 + 到期）+ 题干大字 + 音标 + 出处（+ 提示条，:778-878）→ ④ **一个 TextField**（拼写 1 行、翻译 3 行，:883-901）+ 两个文字按钮「给点提示 / 看答案」+ 全宽「提交」→ ⑤ 作答后出现**反馈卡**（Why 一句 + 逐字对照色块 或 词重合 + 标准答案 + 朗读 + "它在原文里是这样用的"，:981-1101）+ 全宽「下一题」→ ⑥ 结束→**小结卡**（46 号大字正确率 + 用时分布 + 自适应建议 + 错题清单 + 「只练错题」+「明天继续」，:1105-1338）。

### 1.2.4 写译批改（4 个状态共用同一页，`write_review_screen.dart`）
- **compose**（:643-900）：`AppBar「写译批改」`（右侧保存/收藏/记录图标）→ `SegmentedButton` 手写档/电子档 → 手写档时一条 92px 高横向缩略图条 + 相册/拍照按钮 → **一个大输入框**（电子稿）→ 两个并列按钮「先转电子档 / 直接批改手写图」→ 底部全宽「AI 批改」；另有一个小设置入口打开 `_ReviewSettingsSheet`（:1365+，看/改提示词 + 思考档位）。
- **loading**：骨架屏（:952-960）；**error**：公共 ErrorState（:962-972）。
- **result**（:974-1129）：分数圆环卡（数字 0→score 动画，:1142+）+ 一句总评 → 「错误分类汇总」4 张卡（词汇/语法/表达优化/其他）→ 「逐条点评（N）」每条一张卡（可点开追问）→ 「修正后全文」→ 「我的原文」（+手写识别原文）→ 两按钮（修改后再批 / 重新批改）+ 全宽「保存为写译记录」；右下 FAB「追问」。

### 1.2.5 回译练习页（旧，`exercise_screen.dart` 全 212 行）
`AppBar「回译练习」`（右侧得分百分比）→ 顶部色块说明条「📝 将下列中文句子翻译回英语…」→ `ListView` 的 N 张卡（圆序号 + 中文句 + `TextField` 2 行）→ 底部全宽「提交答案」。提交后：输入框 `enabled:false` + 填灰 + 按钮变「返回」。**没有逐句判定、没有参考答案、没有错因**（:138-156, 166-182）。

### 1.2.6 写译记录（`writing_logs_screen.dart`）
`AppBar「写译记录」`（右上"共 N 篇"）→ 骨架/错误态 → 按 `dateKey` 分组的日期头 + 记录卡列表（:54-61, 121+）；可展开、删除、恢复（:289-320）。

### 1.2.7 同质化判定：骨架同构，差异只是"点缀"
**共性（7 条）**
1. 所有页面都是 `Scaffold + ListView + AppCard 纵向堆叠`，没有横向分区、没有画布、没有分栏/时间轴/矩阵类布局；
2. 所有"作答"都收敛成 **TextField + 底部全宽提交按钮**；没有选项网格、连线、拖拽排序、句子拼接、句子改写 diff、批注层、语音输入；
3. 所有"结果"都是 **一张主分数卡 + 若干文本卡**；没有维度雷达/分档条/逐句对齐表/能力项对比；
4. 入口形态一致：`图标盒 + 标题 + 一行说明`（输出首页卡、练习中心开始卡、写译入口 tile 全一样）；
5. 段落结构一致：`AppSectionTitle(标题+副标题) → AppCard`，连"练习中心"和"我的"页的排版节奏也一样；
6. 状态机一致：loading=骨架屏、empty=AppEmpty、error=ErrorState、成功=卡片列表；
7. 反馈都是**一次性**（提交后只出现一张反馈卡），没有"再试一次/换一种表达/看同类题"的分支。

**真差异（只有 3 处，都是细节不是结构）**：drill 有进度条与逐字 diff（:708-719, 1014-1044）；写译有分数圆环与可追问的逐条点评（:1142+, :1034-1043）；写译记录有日期分组。**这正是用户说"练习方式以及练习区的 UI 非常单一同质化"的直接证据**。

> 另：用户在 10-25 截图里骂的"写译批改页整体灰、两个大按钮像禁用、虚线框空态"（见 `HANDOFF-FRONTEND-UPGRADE.md:129-139`）与代码一致：compose 态在浅色主题下几乎全是 `surfaceContainerHighest`+`outlineVariant` 边框，主按钮与次按钮并列（`write_review_screen.dart:760-900`）。

## 1.3 练习过程/结果数据怎么存，有没有回路

### 1.3.1 相关表（全部在 `lib/services/database.dart`）

| 表 | 定义行 | 关键字段 | 谁写 |
|---|---|---|---|
| `vocabulary` | :97-121 | word/translation/original_sentence/word_type/mastery_level/category/material_path/occurrences_json | 阅读器点词、识图识别、听写、词库编辑/导入（`vocab_provider.dart`） |
| `exercises` | :134-146 | article_id/type/source_sentences/reference_answers/user_answers/score | 仅回译练习（`article_provider.dart:125,171`） |
| `writing_logs` | :180-194 | source_type/original_text/corrected_text/score/summary/issues_json/error_summary_json/model/image_paths | 仅写译批改保存/恢复（`write_review_screen.dart:396`、`writing_logs_screen.dart:319`） |
| `drill_plans` | :345-358 | mode/goals/level_note/weeks/per_day/start_date/status | 练习中心（`drill_plan_screen.dart:413,514`） |
| `drill_logs` | :360-373 | mode/plan_id/goals/total/correct/seconds/wrong_words | `drill_screen.dart:543,590` |
| `quiz_results` | :408-419 | kind/ref_id/total/correct/detail_json | **只有**读后测验（`reading_quiz_screen.dart:77`） |
| `error_tags` | :421-433 | source/tag/count/first_at/last_at/status/evidence | **只有**复习答错（`review_screen.dart:218`）与读后测验（`reading_quiz_screen.dart:89`） |
| `word_review` | :247-262 | FSRS：stability/difficulty/due_at/reps/lapses/last_rating | 复习、drill 错题、读后测验、听写、阅读器/书架的"收藏即建卡" |
| `daily_log` | :148-156 | new_words_count/reviewed_count/exercise_completed/study_minutes | 生词入库（`vocab_provider.dart:40`）、回译**生成**（`article_provider.dart:131`） |
| `tutor_tasks` | :435-448 | plan_date/kind/title/payload_json/target_minutes/done_at/result_json | 助理页（`tutor_home.dart:84`） |
| `tutor_messages`/`tutor_conversations`/`tutor_memory` | :454-482 | 对话与长期记忆 | 助理对话/访谈 |

### 1.3.2 回路真相（重要）

| 练习结果 | 是否回流"能力画像/现状分析/周报/助理" | 证据 |
|---|---|---|
| 拼写/翻译的 `drill_logs` | **否**。只在输出模块内部被读（`loadDrillSummary` `drill_plan_screen.dart:239-269`、`output_home.dart:59`）；`LearnerSnapshotLoader`（`learner_snapshot_loader.dart:21-121`）与周报（`weekly_report_screen.dart:74-81`）都**不读** drill_logs | 同左 |
| 写译批改的 `writing_logs` | **否**。只有写译记录页自己读（`writing_logs_screen.dart:32`）。助理快照、周报、错误档案都不读 | 同左 |
| 写译批改的"错处/错误分类" | **不写** `error_tags`（全库 `bumpErrorTag` 只有 2 处调用：`review_screen.dart:218`、`reading_quiz_screen.dart:89`） | 但 `error_archive_screen.dart:13-14` 与 :385-390 的文案声称"写译批改/回译练习都会往里写"，`source` 标签表里还预留了 `'writing'→写译批改`、`'exercise'→回译练习` —— **代码没写、界面预留，属于死标签** | 
| 回译练习 `exercises.score` | **否**。除列表页显示外无任何读取方；`quiz_results` 也没有它的记录 | `article_provider.dart:34-40` |
| drill 错题 → 复习队列 | **是**（唯一真回路）：`drill_screen.dart:519-537` 立刻 `upsertWordReview(dueAt: now)`；但只对**已入库**（vocabId 非空）的词生效（:490-493, 1218） | 同左 |
| 读后测验 → 错误档案/复习 | **是**（第二条真回路）：`reading_quiz_screen.dart:77-108` | 同左 |
| 周报里的任务完成 | `done_at` 被当成"活跃日"证据（`weekly_report_screen.dart:146-152`），但任务勾选是手动的、且点「开始」会先勾完成（见 2.3） | 同左 |

**结论：输出模块是一个"数据孤岛"**。它自己的进度/正确率/错题都只服务它自己的进度条；助理页看到的"近 30 天有没有输出"（`tutor_engine.dart:555-556`）只看 `quiz_results` 的 kind——而 `quiz_results` 目前只有读后测验写入，所以**即使每天做写译批改，助理仍会判定"只有输入没有输出"**。

### 1.3.3 两处"注释/文档说的和代码做的不一致"（重建前必须先纠偏）
1. `database.dart:2042` 注释："词汇量测试 / 读后测验 / 回译 / 听写统一进 `quiz_results`" → 实际只有读后测验调用 `insertQuizResult`；词汇量测试写 Hive `learner_model`（`placement_test_screen.dart:155-217`），回译写 `exercises`，听写完全不写。
2. `error_archive_screen.dart:13-14` 的描述见上；`placement_bank.dart:4-5` 声称"语法题答错即记一次该类薄弱" → `placement_test_screen.dart` 里**没有任何 `bumpErrorTag` 调用**（语法 tag 只用于解释文案与 `extras.last_placement.grammar_score`）。

## 1.4 `drill_planner.dart` / `drill_catalog.dart` 这套地基的价值与可复用面

### 1.4.1 高价值、可直接复用（重建输出模块的地基）

| 资产 | 位置 | 价值 |
|---|---|---|
| **目标目录（8 个目标、4 个族、每目标出题偏好）** | `drill_catalog.dart:88-212`（四六级/考研/雅思托福/出国生活/职场商务/学术工作/兴趣阅读/看剧） | 已有"按需求个性化"的数据模型：`wordLen`/`sentenceLen` 区间、`keywords` 词表、`exam` 标记；`resolve()` 缺省回落兴趣阅读（:216, :260-271）、`normalizeAll()` 统一标签写法（:248-256）。**任何新题型都能复用这套"目标→偏好"结构**，只需给题型加自己的偏好字段 |
| **水平档位 + 由测量数据推档** | `drill_planner.dart:25-56, 482-496` | 3 档（基础/进阶/高阶），优先用 CEFR（含 `B2+`/`雅思6.5` 模糊解析 :499-504），否则词汇量 <3500/<6500 分档；纯函数、有单测 |
| **每日题量建议** | :521-540 | "每日分钟数 × 20 秒/题 × 目标/档位权重"，边界 5~30（默认不传分钟数 → 45 题被 clamp 到 30，即默认每天 30 题） |
| **组题六项加权（可解释排序）** | :559-732（`buildQuestions`/`_questionOf`/`_scoreOf`） | 关键词命中、长度贴合（有 -3 地板，防"反个性化"）、到期优先、掌握度、有原句、水平方向；seed 轮转保证"同一天稳定、换天换题"（`drill_screen.dart:247-249`） |
| **题目与难度模型（数据结构）** | `drill_planner.dart:62-115` `DrillQuestion` | 题面/答案/音标/出处/原句/释义/词条类型/掌握度/是否到期 + 首字母/词数提示；**新题型可以扩字段而不是另起一套** |
| **计划模式的结构化编码** | :315-444 `DrillPlanNote` + `encode/decodePlanNote` | 在只允许写 `drill_plans.level_note` 的约束下塞进 `mode/goals/level/note` 四段，且对脏数据容错；**新增字段要沿用这套"TEXT 列编码"约定或迁移加列** |
| **4 周大纲（纯计算）** | :741-830 | 按目标族类给每周/每日主题（备考=高频词/真题短句回译/长难句主干…；学术/生活/兴趣各一套），"认得出→写得出→用得上→稳得住"四周递进 |
| **自适应** | :838-899 | ≥90% 加量+1 档 / 60~90% 保持 / <60% 减量-1 档，题量 1.25/0.7 倍，边界 5~30；0 视为无数据不动 |
| **进度/统计派生** | :922-1057（`progressOf`/`statsFrom`/`recentRates`） | 从日志重算打卡天数、今日题数、正确率、7 次趋势、用时分布——不存冗余计数器，口径可解释 |
| **判分纯函数** | :1094-1109 | 拼写（忽略大小写全等）、翻译（词袋重合 ≥0.5，返回 hit/ref 供解释） |
| **单测资产** | `test/drill_planner_test.dart`、`test/drill_db_test.dart` | 组题排序、自适应、进度、计划编解码都能直接回归 |

### 1.4.2 半可复用（结构对、口径要扩）
- `DrillMode` 只有 2 个枚举值（`drill_screen.dart:17-53`）——新题型必须扩枚举，且 `mode` 字符串直接落库（:30-39），扩值时要做**旧值兼容**。
- `DrillCatalog` 的偏好只有"词长/句长/关键词"——真题写作/段落翻译需要的是**题型/体裁/话题/句法难度/年份**等维度，要加字段（保持向后兼容的 const 构造）。
- `DrillGoal.keywords` 是"材料是否属于该目标"的代理，本质是**词表匹配**，不是真正的"考试能力项"；新题型的"针对性"不能只靠它。
- `loadDrillSummary`（`drill_plan_screen.dart:239-269`）是三处数据拼装，可拆成通用 `OutputProgressService` 供新题型与助理复用。

### 1.4.3 不可复用/建议重做
- **答题页骨架**：`DrillScreen` 与题型强耦合（拼写/翻译的 UI 差异靠 `isSpelling` 分支写死：:751, 826-836, 1070-1097）——新增 3 种题型就会变成 if/else 泥潭，建议抽象为**题型渲染器**（见 §1.6）。
- **回译练习（exercises 表 + ExerciseScreen + scoring.dart）**：数据结构是"一次练习=一批句子+一份总分"，无法承载逐句 rubric/能力项；且 `article_id` 外键绑死文章。**建议保留表以兼容历史数据，新链路不再使用**。
- **写译批改的评分口径**：`WritingReviewSettings.defaultPrompt` 只要求模型"给 0-100 + 分类错误"，没有档位/维度/依据项（:29-39）——要与"考试评分标准"对齐，prompt 必须重写成 rubric 驱动。
- **注释里的"单测宣称"要核实**：`drill_planner.dart:16` 说"test/drill_planner_test.dart 能直接全测"——文件存在（`test/drill_planner_test.dart`），但本报告**未逐条核对覆盖度**（未证实覆盖率）。

## 1.5 针对"四六级真题写作翻译 / 新概念回译"这类材料：现在缺哪几块

> 用户原话（本次侦察的任务依据）："翻译练习无法给学习者提供针对性的、符合目标的练题（比如四六级考生要近几年真题的写作翻译、或者新概念教材的回译）……重点是让 AI 真的能发挥它'爬资料'的能力，然后根据功能逻辑加工"。

### 缺口 1：材料源（最硬的一块）
- **现有源**只有公开域/公开页面：NPR、VOA、Project Gutenberg 全文、arXiv 摘要、Wikipedia（`material_source.dart:257-330`，可达性实测注释 :349-353），外加"AI 检索规划"（`deepseek_api.dart:108-160`，把中文需求转英文检索词 + 点名公版书/论文/公开文章）与文件导入（`material_import.dart:106-176`，可粘贴 Gutenberg/arXiv 链接自动识别）。
- **没有**：四六级/考研/雅思/托福真题语料（版权与可得性都未解决）、新概念等教材语料（版权）、"近年真题"的时间维度（年份/套卷/题型分区）。
- **可借力**：`materials` 表已有 `cefr/flesch/coverage/new_word_density/word_count/difficulty_json/cover_url/source/source_id/url/license`（`database.dart:264-296`）——**它就是"材料难度与来源"的现成元数据**；`material_import.dart` 的抓取/入库/切块链路可直接复用给"用户自备真题 PDF/文本"（先支持用户导入，再谈 AI 爬）。
- **未证实**：真题的合法获取路径、能否稳定抓取、是否需要用户自备文件——这三件必须由用户拍板（涉及版权与合规，不能由代码单方面决定）。

### 缺口 2：题目结构（没有"题"的概念）
现有结构只有"中文→英文词/句"一种填空式（`DrillQuestion` `drill_planner.dart:62-115`）。缺：
- **写作任务**：题干（题目要求/提纲/图表/书信场景）、字数范围、建议时长、读者对象、可用提示（outline/关键词）；
- **段落级翻译**（四六级段落汉译英）：整段中文 + 分句切分 + 关键表达提示 + 参考译文；
- **教材回译**：课文分句/分段 → 中文译文 → 用户回译 → 与原文逐句对齐；
- **客观新题型**：选词填空、句子改写、错误改正、句子排序（这些可以**本地可判**，且能覆盖"语法"要素）；
- **题组/卷面**概念（一套题 = 若干 section + 建议时长 + 满分），目前完全没有。

### 缺口 3：评分标准（rubric）
- 翻译判分=词袋重合 0.5（`drill_planner.dart:1101-1109`），**无词形还原、无语序、无语法、无扣分档**；
- 写译批改=模型自由 0-100（`writing_review_settings.dart:29-39`），**无维度、无档位描述、无"依据项"**；
- 缺一张 `rubrics` 表与"分档描述/维度权重/判分依据"结构；也缺"同一篇作文两次评分一致性"的复核机制。
- **可借力**：项目已有"证据优先"的方法论（`tutor_engine.dart:3-11`、`weekly_report.dart:1-16` 都要求"无证据不下结论"），rubric 评分完全可以沿用"分数必须带依据项"的纪律。

### 缺口 4：能力项映射
- 目前"能力项"只有 `error_tags.tag`（自由字符串，且只有复习/读后测验在写），**没有维度（词汇/语法/篇章/得体/翻译技巧）与时间序列**；
- `quiz_results.detail_json` 是自由结构，`writing_logs.error_summary_json` 只有 4 类（词汇/语法/表达优化/其他，`writing_log.dart:39`），**都没映射到 CEFR/CET 分项**；
- 结果没有任何一处汇总成"这个人的写作能力项画像"，所以"针对性出题"缺少**选题输入**（不知道该补哪一项）。

### 缺口 5：生成与缓存链
- 现有 AI 链：文章生成（`deepseek_api.dart:41`）、材料检索规划（:119）、翻译（:238/:252）、抽句回译（:314）、批改（`doubao_api.dart:839/875`）、追问流（:1073）。**缺"按题型模板生成题组 + 参考答案 + rubric + 依据"的链路**。
- 也**缺题库缓存表**：现在抽句回译每次都重新生成、无校对、无版本、无复用；AI 生成内容没有"待校对/已校对"状态，直接进 UI。
- AI 是否能在一次调用里稳定产出"题目+答案+分档 rubric"——**未实测**（本次只读代码，未调 API）。

## 1.6 输出模块最小重建方案（只给结构，不给视觉设计）

> 目标：让输出从"生词本镜像"升级为"有题型、有材料源、有 rubric、有回流"的练习系统，同时**不推倒** `DrillPlanner` 的纯函数资产。

**P0 内容层（新表，dbVersion 18→19）**
- `exercise_sets`：题组/卷面。`id, source(ai/builtin/user_import/exam), exam_type(cet4/cet6/kaoyan/ielts/nce/none), paper_year, paper_label, section(reading_translation/writing/back_translation/blank_filling), title, difficulty(cefr), goals_json, rubric_id, material_id, license_note, verify_status(pending/verified), created_at`
- `exercise_items`：单题。`id, set_id, idx, type, prompt_zh, prompt_en, reference_answer, accepted_answers_json, rubric_id, ability_tags_json, grammar_points_json, word_count, source_span, audio_ref`
- `rubrics`：`id, type, scoring_mode(objective/ai_rubric/manual), dimensions_json([{key,label,weight}]), bands_json([{score_range,label,desc}]), prompt_template`
- `output_attempts`：作答明细（替换/补充 `drill_logs`）：`id, item_id/set_id, mode, answer, correct, score_json(维度分), seconds, plan_id, created_at`
- 迁移：`AppConstants.dbVersion 18→19`（`constants.dart:121`），沿用 `_ensureTable` 幂等写法（`database.dart:520-660` 已有范式）。

**P1 出题层（新服务，纯函数 + API 封装分离）**
- `OutputComposer`：输入（goals/exam_type/level/能力弱点/可用材料/题量）→ 输出（题组 + rubric + 依据）；复用 `DrillCatalog` 目标偏好与 `DrillPlanner.levelOf`。
- 两条来源：① `user_import`/`exam` 题库（先支持**用户自己导入真题文本**，AI 只做"切题+结构化+生成参考与 rubric"，规避版权）；② `ai` 生成（用 AI 爬/检索到的公开语料 + 模板出题，落 `verify_status=pending` 等校对）。
- 旧的拼写/翻译保留为 `objective` 题型分支，继续读生词本（保留现有用户数据连续性）。

**P2 评分层**
- objective：选择题/排序/拼写（沿用现有 `judgeSpelling` 风格，补 `judgeTranslation` 的 lemma 化——项目已有 `services/lemma.dart`）；
- ai_rubric：一次调用返回 `{score, dimensions:[{key,score,band,evidence}], issues:[{span,type,reason}], correction, summary}`，**必须先给依据项再给分**；提示词由 `rubrics.prompt_template` 注入；
- 写译批改复用同一评分层，把 `WritingReviewSettings.defaultPrompt` 升级为 rubric 版（保留"可查看/可修改/可恢复默认"能力）。

**P3 UI 骨架族（至少 4 种，替换"一套骨架套所有"）**
- a) 逐题作答骨架（可保留现有 drill 页，作为 objective 题型）；
- b) 篇章任务骨架（写作/段落翻译：题目要求 + 提示 + 字数/计时 + 草稿区 + 提交）；
- c) 对照复盘骨架（逐句/逐段 diff + rubric 维度分 + 分档位置 + 定位到原句 + 重写入口）——**这是目前完全缺失、也最能体现"专业"的一屏**；
- d) 题库浏览骨架（按考试/年份/题型/难度筛选的题组卡 → 开练）。
- 四个骨架共享 `DesignToken/AppCard`，但**布局拓扑必须不同**（分栏、时间轴、句子对齐、维度条），否则用户又会说"换排列"。

**P4 回流层**
- `output_attempts`/`writing_logs` → `LearnerSnapshotLoader` 新增字段（drill stats、writing scores、rubric 维度分）；
- 评分层写 `error_tags`（带维度：拼写/词形/语序/时态/篇章衔接…），并给 `error_tags` 加维度列或约定 `source='output'`；
- 周报新增"输出"块（本周写作/翻译产出、rubric 维度变化、错误热点）；
- 助理现状分析读这些字段（见 2.4 的 `ability_snapshots` 设计）。

**验收建议（可量化）**
1. 同一目标（如四六级）能出 3 种题型，且每题都带"为什么给你出这题"（目标/能力项/材料来源）；
2. 交一篇作文后，结果页有 ≥3 个维度分 + 每个分有依据句；
3. 做完练习后，助理页"近 30 天只有输入没有输出"不再误报；周报出现输出块；
4. 旧数据（drill_logs/exercises/writing_logs）不迁移丢失、旧页面可回滚。

---

# 第二部分 · 学习助理

> 入口：底栏「助理」（`bottom_nav.dart:18,81`）→ `TutorHomeScreen`（`lib/screens/tutor/tutor_home.dart`）。

## 2.1 "需求询问"界面：单选的实锤与存法

### 2.1.1 界面在哪
`lib/screens/tutor/tutor_interview_screen.dart`（标题「先聊聊你的情况」，6 步）。用户说的"四六级/兴趣阅读不能多选"实锤在 **第 1 步**：

```dart
// tutor_interview_screen.dart:44-48
_Step(
  question: '你学英语,最主要想用它做什么?',
  why: '这决定我给你排什么材料、练什么题型',
  options: ['四六级', '考研', '雅思/托福', '出国生活', '工作/学术', '兴趣阅读', '看剧看视频'],
),   // ← 没有 multi: true，默认 false（_Step.multi 默认值见 :38）
```
只有第 5 步「想读什么题材」与第 6 步「不想看的内容」是 `multi: true`（:64-75）；单选逻辑在 `_toggle`（:91-103）：非多选时先 `clear()` 再 `add`。

另有一个**旧版需求询问**也全是单选：`lib/screens/input/learner_profile_screen.dart:109-125`「学习目的」chip（选项 `读懂原版书/应试提分/日常工作邮件/口语交流/看剧听播客/写作输出`，`material_recommendation.dart:143-150`），入口在「输入 → AI 找材料 → 学习画像」（`ai_material_search.dart:100,309`）。它与助理是两套存储（见下）。

### 2.1.2 选择结果存哪
`_finish()`（`tutor_interview_screen.dart:118-213`）：
- 第 1 步的**一个**字符串被拼成 `'四六级(半年内)'` 写进 `LearnerModel.goal`（`ProfileField<String>`，:126-141，`source=self, confidence=0.9`）；
- 每天分钟数 → `dailyMinutes`（:142-149、`_minutesOf` :215-221）；题材 → `interests`（:150-157）；不想看 → `blockedTopics`（:158）；
- 同时把 5 行人话写进 `tutor_memory(kind:'preference')`（:170-180，`DatabaseService.addTutorMemory` `database.dart:3194`）；
- **不写** `LearnerModel.goals`（多选字段，`learner_model.dart:109-113`）——即使模型里已有该字段。

### 2.1.3 后续怎么用（以及断在哪）
- 助理侧：`TutorEngine.learnerContextLine` 只读 `model.goal`（`tutor_engine.dart:531-546`），`goal` 只是**一个字符串**，用于拼进 AI 证据包；诊断规则本身**不按目标分支**（11 条规则里没有一条读 goal/goals）。
- 练习侧：`DrillCatalog` 多选目标写的是 `LearnerModel.goals`（`drill_plan_screen.dart:46-59`「showDrillGoalPicker」），输出首页把 `goals + goal` 合并展示（`output_home.dart:172-175`）。→ **两套目标体系不互通**：助理访谈的目标不会进练习多选，练习多选也不回给访谈。
- **丢数据**：访谈页有自由输入框「想补充点什么?」（:283-293），但 `_finish()` **只读 `_picked`、从不读 `_freeCtrl`**（:123 `answerAt` 只看 `_picked[i]`）——用户打的补充文字**直接丢失**。

### 2.1.4 改成多选要动的点（最小）
1. `tutor_interview_screen.dart:44-48` 加 `multi: true`；
2. `_finish()` 把第 1 步写成 `goals: (选中的多个标签)` 并同步 `goal = 第一个`（与 `drill_plan_screen.dart:48-59` 同一口径，避免第三个字段）；
3. `TutorEngine.learnerContextLine`（`learnerContextLine` :531-546）与 `evidencePrompt`（:488-528）读 `goals`（当前只读 `goal`）；
4. `tutor_home.dart:357-363` 的访谈回显改成多标签；`LearnerModelStore.saveSelfReported`（`learner_model_store.dart:120-177`）目前只有 `goal` 参数，**要加 `List<String>? goals`**（否则草稿表单与访谈写不进去）；
5. `learner_profile_screen.dart:109-125` 旧画像页同步改多选（或下线，统一到访谈/练习中心）。

## 2.2 "学习现状分析"：文案哪来、数据哪来、现在到底说什么

### 2.2.1 代码位置与链路
- 生成：**本地规则引擎** `lib/services/tutor_engine.dart` `diagnose(snapshot)`（:200-381）→ `List<TutorFinding>`（id/severity/title/evidence/action/jump，:41-72）。
- 数据组装：`lib/services/learner_snapshot_loader.dart:21-121`（任一查询失败降级为 0，绝不让页面白屏）。
- 渲染：`tutor_home.dart:249-295`（`AppSectionHeader「学习现状分析」01` + 每条约一张卡，卡片 `_buildFindingCard` :732-794：图标+标题+**依据全文**+→建议+跳转按钮）；两条 AI 按钮走对话（:267-292「让 AI 排规划 / 看我最薄弱的」）。
- **AI 不生成现状分析**：AI 只在对话里被喂证据包（`tutor_chat_screen.dart:439-449` + `TutorEngine.evidencePrompt` `tutor_engine.dart:488-528`），禁止编造新结论。

### 2.2.2 现在到底输出哪些句子（11 条，按代码顺序）
| id | 触发条件（代码） | 标题示例（代码原文） | 依据/数据 |
|---|---|---|---|
| `no_baseline` | 没有 `source=test` 的词汇量基线（:204-217, :550-553） | 「先花 5 分钟测出你的词汇量基线」 | 生词本 N 词 / 无水平数据 |
| `review_backlog` | 到期 >0 且过期 ≥50(警告)/≥200(行动)（:220-237） | 「复习堆积:N 个词已经过期」 | `word_review.due_at` |
| `no_review_system` | 生词 ≥50 且复习状态 0 条（:240-250） | 「生词本在变成"收藏夹"」 | vocab 数 / word_review 数 |
| `input_only` | 近 30 天读过词 >0 且 `quizAccuracy` 里除 vocab_placement 无其他 kind（:253-264, :555-556） | 「近 30 天只有输入,没有输出」 | reading_sessions / quiz_results |
| `material_too_hard` | 最近材料最低覆盖率 <90%（:267-282） | 「《X》对你偏难」 | materials.coverage |
| `material_too_easy` | 最高覆盖率 ≥99%（:285-299） | 「《X》几乎没有生词」 | 同上 |
| `repeating_errors` | `error_tags` 中 status=active 且 count≥3（:302-317） | 「重复出错:时态」 | error_tags |
| `low_comprehension` | 读后测验正确率 <50%（:320-332） | 「读后测验正确率偏低」 | quiz_results kind=reading_comprehension |
| `slow_reading` | 实测 wpm <120（:335-346） | 「阅读速度偏慢(实测 N 词/分)」 | reading_sessions.wpm |
| `long_break` | 近 30 天活跃 ≤2 天且连续 0（:349-359） | 「最近几乎没有学习记录」 | daily_log |
| `healthy_next_step` | 全部是 info 时兜底（:362-373） | 「节奏是稳的,可以加一点难度」 | 综合 |

> 另外 `TutorEngine.summaryLine`（:469-484，本该是"顶部一句话总结"）**已实现但 tutor_home 从未调用**——现状分析页顶部其实没有摘要。
> UI 也**没有"能力项卡"**：没有"词汇量 xxx / 语法 xxx / 写作 xxx"这类第一层结论，用户的批评（"只提供没完成的事'单词 xx 没复习'浮于表面，而不是分析更专业想'词汇量 xxx''语法 xxx'"）与代码完全吻合：11 条里 8 条是行为债/材料匹配，只有 `no_baseline` 与 `healthy_next_step` 带能力语义，且都是"测/不测"级别，没有分项能力值。

### 2.2.3 数据来源是哪几张表
`LearnerSnapshot`（`tutor_engine.dart:124-182`）字段 ← `LearnerSnapshotLoader.load()`（`learner_snapshot_loader.dart:33-120`）：

| 维度 | 字段 | 来源 |
|---|---|---|
| 画像 | model（CEFR/词汇量/目标/每日分钟/兴趣/屏蔽） | **Hive** `learner_model_v2`（`learner_model_store.dart:16-36`） |
| 词汇 | totalVocab / 三档掌握度 / 近 7 天新增 | VocabProvider 内存列表 + `vocabulary.mastery_level` + `getVocabCountSince` |
| 复习 | dueReviewCount / overdueCount / trackedReviewCount | `word_review`（FSRS） |
| 输入 | 30 天 sessions/words/minutes/avgWpm；在学/读完材料；最近 5 份材料+覆盖率+进度 | `reading_sessions`、`materials`+`material_progress` |
| 输出与反馈 | quizAccuracy（kind→正确率）、errorTags（active） | `quiz_results`、`error_tags` |
| 习惯 | streakDays / activeDays30d | `daily_log`（`stats_provider` 内存） |

**注意：这份快照里没有 `drill_logs`、`writing_logs`、`exercises`**（见 1.3.2），所以"输出"维度实际是空的。

### 2.2.4 更专业的现状分析：可用的真实数据有哪些
1. **`vocab_estimator.dart`（词汇量测量，28KB，最硬的一块）**
   - 方法：Yes/No 认词测试 + 伪词校准（Meara & Buxton 1987 范式，:4-42 注释写明依据与 6 条局限）；6 个词频档 b1..b6（名次 1..20000，:49-88），每档抽样 + 伪词穿插；输出 `estimate/low/high/falseAlarmRate/bandHitRate/cefr/earlyStopped/lowConfidence`（:112-241）；速测 ≈64 题（12/档 + 4 伪词）、完整版 ≈136 题（20/档 + 8 伪词，:245-256）；语法/阅读小题分数由 UI 注入合并（:159-163, :624-733）。**但它只把结果写进 Hive（`placement_test_screen.dart:175-202`），页面上只显示一次；`bandHitRate`（"你在哪一档开始掉"）没有进现状分析。**
2. **`weekly_report.dart`（周报规则引擎，纯函数）**
   - 输入 14 项（activeDates/阅读 sessions/words/minutes/新词/复习数/遗忘数/读完材料/未读完材料/测验正确率/active 错误/reviewBuckets/未来 7 天 forecast/每日分钟，:19-78）；输出 activeDays/wordsRead/minutesRead/newWords/reviewsDone/materialsFinished/quizAccuracy/topErrors/highlights(≤4)/suggestions(≤3)/forecast/isActive（:104-157）；每条结论必带数字（:257-404）。**它只出现在「我的 → 周报」（`profile_home.dart:168`），助理页读不到它的结论**（只复用了它的取数方式）。
3. **可用的其他真实数据**
   - FSRS：`word_review.stability/difficulty/reps/lapses/last_rating`（`database.dart:247-262`）→ 记忆强度、遗忘率；
   - 阅读：`reading_sessions` 的 words/lookups/wpm + `material_progress` 的 percent/lookups/picked_words → 阅读速度、查词密度、完成率；
   - 材料难度：`materials.cefr/flesch/coverage/new_word_density`；
   - 错误：`error_tags` 的 source/tag/count/first_at/last_at → 错误热点与复发；
   - 练习：`drill_logs`（正确率/题量/用时）、`writing_logs`（分数/4 类错误汇总/逐条 issues）、`quiz_results`（正确率）；
   - 习惯：`daily_log`（新词/复习/练习/分钟）。
4. **缺什么（要做到"词汇量 xxx / 语法 xxx / 写作 xxx"）**
   - **语法能力项**：只有完整版词汇量测试里的 **5 道**四选一（时态/冠词/介词/主谓一致/虚拟语气，`placement_bank.dart:36-78`），结果只存 `extras.last_placement.grammar_score`（`placement_test_screen.dart:184-200`），**错题不写 error_tags、不累积、不按语法点分项**；
   - **写作能力项**：`writing_logs.score` 是模型自由分，`error_summary_json` 只有 4 类；没有维度分/档位/时间序列；
   - **听力数据**：听写不落成绩（`dictation_screen.dart:110-166`），`reading_sessions` 也不区分听力；无法说"听力 xxx"；
   - **口语**：未开放（`output_home.dart:88-166` 明说）；
   - **能力项时间序列**：`error_tags` 有时间但无维度；没有任何"能力值随时间变化"的表；
   - **输出回流**：drill/writing 不进快照（1.3.2）。

## 2.3 "学习任务"：怎么生成、能不能编辑、有没有追踪

### 2.3.1 生成链
`TutorEngine.planTasks(snapshot)`（`tutor_engine.dart:384-466`，纯规则、无 AI）→ 首次进入助理页时落库：`tutor_home.dart:81-97`「今天没有任务就生成一次」（`getTutorTasks(snap.now)` 为空才插，**每天一份、不覆盖已有**）→ `DatabaseService.insertTutorTask`（`database.dart:2425-2446`，表 `tutor_tasks` :435-448）。

### 2.3.2 任务形态（最多 4 条，按插入顺序截断 :460-464）
1. `review`：有到期词时永远第一条（`复习 N 个词(今日到期 M)`，:394-404）；
2. `placement`：没基线时（:406-415）；
3. `read`：优先"继续读《X》(已读 N%)"，否则"从材料中心挑一份 95-98% 覆盖率材料精读"（:417-439）；
4. `write`：30 天无输出时"用今天的新词写 3 句话(或做一次回译)"，否则新词≥10 时"把 10 个新词各写一个句子"（:441-458）。
每条带 `reason`（"来自诊断:xxx"）与 `jump`（跳哪个 tab），payload 存 `reason/jump/jumpArg`（`tutor_home.dart:89-93`）。

### 2.3.3 能否编辑 / 完成状态 / 追踪
- **不能编辑**：UI 只有「开始」/「标记完成」/「撤销完成」（`tutor_home.dart:501-545` 主卡、:662-717 列表卡）。DB 有 `deleteTutorTask`（`database.dart:2510`）但**无 UI 调用**；没有新建、改标题、改时长、改类型、排序、跳过。
- **完成状态**：`done_at`（勾选时间）；`result_json` 字段存在但**UI 从不写**（`completeTutorTask(id)` 调用不带 result，`tutor_home.dart:159`）。
- **严重口径 bug**：主卡「开始」按钮**先 `_completeTask(first)` 再跳转**（`tutor_home.dart:518-523`）——用户一点"开始"任务就记为完成，实际有没有做无人对账。列表卡「开始」只跳转不勾（:708-712），两处口径不一致。
- **追踪/复盘**：只有周报把 `done_at` 当"活跃日"证据（`weekly_report_screen.dart:146-152`）；**没有**完成率/按时率/计划 vs 实际/连续跳过/按类型的产出统计；也没有任何页面回看历史任务。
- 桌面小组件会读今日任务（`widget_service.dart:52`），但只是镜像。

### 2.3.4 与"数据追踪复盘与指导"的差距（用户原话的落点）
1. 任务 = 模板句子，不是"可执行对象"（没有关联到具体材料/具体词表/具体题组，jump 只是切 tab）；
2. 无自定义任务；
3. 无状态机（只有 pending/done 两态 + 手动勾选）；
4. 无行为对账（勾了"读 20 分钟" ≠ 真的读了）；
5. 无复盘视图；
6. 无"指导"闭环（诊断 → 任务 → 结果 → 新诊断 这条链在任务处断了）。

## 2.4 "自定义任务 + 数据追踪复盘 + 指导"的最小可行设计

> 约束：不推倒 `tutor_tasks`（已有用户数据与周报读取），用"扩列 + 新表"落地；迁移沿用现有 dbVersion 18→19 + `_ensureTable` 幂等模式（`database.dart:520-660`）。

### 2.4.1 表/字段
1. **`tutor_tasks` 扩列**（保历史、周报不用改读法）：
   `origin TEXT DEFAULT 'auto'`（auto/custom）、`status TEXT DEFAULT 'pending'`（pending/active/done/skipped/expired）、`started_at TEXT`、`actual_minutes INTEGER`、`note TEXT`、`parent_id INTEGER`（周期模板）、`goal_tag TEXT`（关联目标需求，便于按目标复盘）。
2. **新表 `task_events`**：`id, task_id, event(create/start/submit/skip/reopen/edit/expire), at, payload_json` —— 追踪用原子事件，不覆盖历史。
3. **新表 `ability_snapshots`**（能力项时间序列，供"更专业的现状分析"与"指导"）：`id, date, dimension(vocab_size/vocab_depth/grammar/listening/reading/writing/translation), score REAL, band TEXT, detail_json, source(test/inferred/behavior), created_at`。
   - 写入时机：词汇量测试、写作批改、drill 完成、周报生成、任务完成结算；
   - 只读派生（`ability_snapshots` 由其他表算出，不是手填）。
4. **新表 `ability_items`**（能力项字典）：`code, label, parent, exam_type_json, description` —— 让"词汇/语法/写作"有稳定 key，避免 `error_tags.tag` 自由字符串。
5. 如要"关联到具体材料/题组"：`target_json`（`{material_id, vocab_scope, exercise_set_id, exam_type}`），无需新表。

### 2.4.2 状态机（明确到可写代码）
```
pending ──开始(进入关联页/点开始)──> active ──提交结果或手动勾──> done
pending/active ──用户跳过──> skipped
pending/active ──次日结算未做──> expired
done ──撤销──> pending（task_events 记 reopen，不删事件）
skipped ──重新打开──> pending
```
- 结算放 `LearnerSnapshotLoader`（或独立 `TaskSettlement` 服务，启动时跑一次），**只对 `plan_date < 今天` 且非终态的 auto 任务生效**；
- `done` 的判定优先级：`result_json` 有真实结果 > 手动勾（手动勾要标记 `manual=true`，复盘时可区分可信度）。

### 2.4.3 UI（最小三屏）
1. **今日任务列表（改造 `tutor_home.dart:298-326`）**：任务卡显示 状态点/标题/预计分钟/关联对象/来源(auto=为什么派你:reason；custom=用户自己的备注)；操作=开始/跳过/编辑(仅 custom)/完成；
2. **新建/编辑任务弹层**：标题、类型（读/复习/练习/写译/听说/自定义）、预计分钟、关联材料或词库范围（可选）、重复规则（无/每天/每周）、备注；auto 任务只允许"跳过/改时长"，不允许改内容（保持"专业建议"的权威性）；
3. **复盘页**（新页，入口放任务区顶部）：本周完成率/按时率/计划 vs 实际分钟/按类型产出（正确率、作文分、复习词数、精读词数）+ 连续跳过提示 + "下周建议"（复用 `WeeklyReportBuilder` 的风格：每条必带数字）。

### 2.4.4 追踪指标（都能从现有/新增数据算）
- 完成率 = done /（done+skipped+expired）；按时率 = 当日完成 / done；
- `actual_minutes / scheduled_minutes` 比（偏差 >50% 触发"任务量不合身"提示）；
- 连续跳过天数、任务类型分布（是否长期只做复习不做输出）；
- 产出指标：`drill_logs` 正确率、`writing_logs` 分数/维度、`quiz_results` 正确率、复习词数、精读词数；
- 与能力项关联：任务 → `ability_snapshots` 的维度变化（"这周写作维度 +6"）。

### 2.4.5 "指导"闭环（扩 `TutorEngine.diagnose` 即可，不用 AI）
新增规则（每条仍要求"证据+动作"，保持现有纪律）：
- `task_stalled`：连续 N 天有任务未完成/跳过 → 建议把任务拆小；
- `plan_overload`：连续 2 周实际/预计 <0.6 → 建议下调每日任务量；
- `ability_stalled`：某维度 4 周内 `ability_snapshots` 无变化 → 换练法；
- `output_missing`（替换现有 `input_only`）：改为读 `drill_logs`/`writing_logs`/`quiz_results` 三类，消除误报；
- `task_done_no_result`：任务被手动勾但无关联行为 → 提示"这次没留下练习记录"。
AI 只在"措辞与排序"层介入（保持 `tutor_chat_screen.dart:439-449` 的"只基于证据包"约束）。

## 2.5 助理侧可复用资产 / 风险

**可直接复用**
- `TutorEngine.diagnose/planTasks/evidencePrompt` 的**"规则先于 AI、无证据不下结论"**架构（`tutor_engine.dart:1-11`）——这是本项目最值钱的方法论资产；
- `LearnerSnapshotLoader` 的降级容错（:167-174）与 `streakDays` 唯一实现（:139-161）；
- `WeeklyReportBuilder` 的"每条结论必带数字"写法（`weekly_report.dart:257-404`）；
- `vocab_estimator` 的测量学实现与 6 条诚实局限（:4-42）、`placement_bank` 的语法 tag 设计（:24-33）；
- 用户模型的 `ProfileField(source/confidence)` 三来源机制（`learner_model.dart:13-88`）——能力项快照也应带 source/confidence；
- 单测：`test/tutor_engine_test.dart`、`test/weekly_report_test.dart`、`test/vocab_estimator_test.dart`、`test/learner_model_test.dart`。

**风险**
- `tutor_tasks` 已有历史数据与周报/桌面小组件读它（`weekly_report_screen.dart:81`、`widget_service.dart:52`），**改结构必须向后兼容**（扩列 + 默认值，不删字段）；
- 知识点：`error_tags.tag` 已经是自由字符串且有历史数据（复习/读后测验），加维度要**保留原 tag 语义**并做映射，不能清空重建；
- 访谈/画像/练习中心**三处目标写法不一致**（`goal` 单值 vs `goals` 多值 vs `LearnerProfile.goal` 老存储），改多选时一次性统一，否则会出"勾了不生效"的老问题（项目已有前科：`drill_catalog.dart:6-16` 注释就是为此写的）。

---

# 附录 A · 代码事实核对表（注释/文档声称 vs 实际）

| # | 声称 | 实际 | 位置 |
|---|---|---|---|
| 1 | `quiz_results` 收纳"词汇量测试/读后测验/回译/听写" | 只有读后测验写入 | `database.dart:2042` vs `reading_quiz_screen.dart:77` |
| 2 | `error_tags` 由"写译批改/读后测验/回译练习/复习"共同写入 | 只有复习 + 读后测验写入；写译/回译无调用 | `error_archive_screen.dart:13-14,385-390` vs grep `bumpErrorTag` |
| 3 | 完整版语法题"答错即记一次该类薄弱" | 只算分存 extras，不写 error_tags | `placement_bank.dart:4-5` vs `placement_test_screen.dart:155-217` |
| 4 | `TutorEngine.summaryLine` 是"导师页顶部一句话" | tutor_home 从未调用（死代码） | `tutor_engine.dart:469-484` vs `tutor_home.dart` 全文 |
| 5 | 回译练习判分"按词重合率" | 只对**新的** exercises 生效；旧数据走长度启发式 | `scoring.dart:14-16` |
| 6 | 助理"已了解你的目标/时间/题材" | 访谈自由补充框内容被丢弃 | `tutor_interview_screen.dart:283-293` vs `_finish` :118-213 |

# 附录 B · 未证实 / 需用户拍板

1. **未证实**（本次只读代码）：四六级真题/新概念课文的合法获取与抓取可行性；AI 一次调用能否稳定产出"题目+答案+rubric"；现有 `writing_logs`/`drill_logs` 的实际使用量（未读真机 DB）；现有单测覆盖度。
2. **需用户拍板**：
   - 真题/教材内容走"用户自备导入"还是"AI 爬公开源"（涉及版权，不能由代码单方面决定）；
   - 写作/翻译评分是否以**官方评分标准（四六级写作 15 分档、翻译 15 分档）**为准；
   - 学习助理的"能力项"到底要几维（建议：词汇量/词汇深度/语法/写作/翻译/听力 六维，口语暂缺）；
   - 自定义任务是否需要"周期任务"（建议先做一次性任务 + 每天/每周两种重复，够用且迁移小）。
