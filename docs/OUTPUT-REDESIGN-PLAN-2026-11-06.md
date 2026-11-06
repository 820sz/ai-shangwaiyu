# 输出链路视觉重做 · 方案与 P0 根因（2026-11-06）

> 范围：输出板块（四阶设置、答题页、批改结果、写译工作台、题库、练习中心、真题抓取、旧计划页）。
> 听力不做。本文只给**方案 + 根因 + 改动清单**，**不改 lib/ 生产代码**。
> 真实渲染图（同屏两种设计）见文末「渲染产出」，由 `test/output_preview_render_test.dart` 生成。
>
> 用户 2026-11-06 20:33 追加的两个硬问题优先（P0），视觉方向收敛为 2 个（A/B）。

---

## 0. 一句话结论

- **P0-1 来源缺失不是「没数据」，是「有列不写」**：`exercise_sets` 表**本来就有** `paper_year` / `paper_label`
  两列（`lib/services/database.dart:394`、`:395`），但入库时 `paper_label` 被硬编码成空串
  （`lib/screens/output/practice_setup_screen.dart:406`），`paper_year` 干脆没写；同时年份/套数在**检索→出题→入库**链路上
  被逐层丢掉（3 处），UI 也从不展示（题库卡只拼「来源/分区/日期」`practice_history_screen.dart:230`）。
  → **零迁移**即可修好：补 2 个字段、1 个纯函数、3 个展示点。
- **P0-2 四六级混排是「两层问题」**：① 用户目标只有「四六级」一个选项，无法表达"只练六级"
  （`lib/services/drill_catalog.dart:90-91`）；② 存储层其实有 `exam_type` 且查询支持按它过滤
  （`database.dart:2567-2597`），**但题库页调查询时不传筛选**（`practice_history_screen.dart:45`），
  且两套"目标→考试类型"映射互相打架（中文标签在材料链路被映射成 `none`，真题链路把「四六级」一律当 `cet4`）。
  → **一期不用改 DB**：加筛选行 + 修映射 + 用标题/来源做一次性回填；拆「四级/六级」目标属于二期，需用户确认。

---

## 一、P0-1「练习材料没标来源/年份/套数」根因

### 1.1 调用链与丢失点（真题·写篇）

| # | 环节 | 位置 | 现状 | 丢失了什么 |
|---|---|---|---|---|
| ① | 入口选择 | `practice_setup_screen.dart:319-397`，弹层只有「写作真题 / 翻译真题」两项（`:327-361`） | 用户在入口**只能选题型**，没有年份/套数可选 | 「用户想要哪一年哪一套」这件事在入口就不存在 |
| ② | 调用出题器 | `practice_setup_screen.dart:369-373`：`composeFromExam(examType: exam, section: section, levelHint: _levelHint)` | **不传 `year`**（该参数存在，`output_composer.dart:999`） | `year` 永远 `null` |
| ③ | 检索结果 | `output_composer.dart:1013-1027`：`hits` 只取 `hit.url` + `page.content` | 搜索命中的**页面标题 / 发布时间**被丢掉，只留 URL + 正文 | 页标题里的「2023 年 12 月第 1 套」再也回不来 |
| ④ | 出题提示词 | `output_composer.dart:517-529`：system 第 2 条「**禁止编造『某年真题』标签**」（`:526`），返回模板只要 `prompt_zh/prompt_en/reference/word_count/hint`（`:520-523`） | 防编造是对的；但**也没要求模型"只从正文/标题抄年份套数"** | 模型不会回传试卷身份 |
| ⑤ | 组装题组 | `output_composer.dart:1064-1067`：`title: '…真题($yearText)'`，`yearText = year != null ? '$year 年' : '近年'` | 只能靠入参 year（恒 null）→ 标题永远是「近年」 | 年份/套数进不了 title |
| ⑥ | 题组数据模型 | `OutputSetSpec`（`output_composer.dart:241-301`）字段只有 `examType/licenseNote/sourceUrls/verifyStatus` | **没有 `paperYear` / `paperLabel` / 套号字段** | 结构上无处安放 |
| ⑦ | 入库 | `practice_setup_screen.dart:400-417`：`'paper_label': ''`（`:406`），无 `paper_year` | 硬编码空串 + 缺字段 | **DB 的两列被写入端丢弃（关键根因）** |
| ⑧ | 单题来源 | `OutputTaskSpec.sourceUrl` 存在（`output_composer.dart:116`，`toJson` 也带 `source_url` `:200`），但 `_saveSet` 只写 `source_span`（`practice_setup_screen.dart:431`）；`exercise_items` 表**没有 source_url 列**（`database.dart:409-426`） | 单题 URL 只在内存里活一次 | 重练/复盘时单题来源永久丢失（仅组级 `license_note` 留有 URL 串，`:414`） |
| ⑨ | 展示·题库 | `practice_history_screen.dart:230-239`：meta 只拼「来源标签 · 分区 · 日期 · 校对」 | 不显示等级/年份/套数/来源站点（`getExerciseSet` 能取到 `paper_*`，`:65`） | 用户看到的题库像"无名卷子" |
| ⑩ | 展示·答题页 | `practice_flow_screen.dart:252-256`：仅当 `source == 'exam'` 显示「真题来源 · 已标注」 | 不展开年份/套数/URL；`OutputSetSpec.hasExamSource`（`output_composer.dart:286-288`）设计好了但**全 UI 0 引用** | 用户无法当场核对"这题哪来的" |
| ⑪ | 历史重练 | `practice_history_screen.dart:85-93` 还原 `OutputSetSpec` 时只带 title/examType/section/rubric/tasks | 不还原 `licenseNote` / `sourceUrls` / `paper_*` | 从题库点进去后，来源信息再次消失 |

> 补充：备份已同步 `paper_year/paper_label`（`lib/services/backup_service.dart:989-999`），
> 所以补这两个字段**不会破坏备份兼容**，也不需要迁移。

### 1.2 修法（零迁移，建议一期做）

| 步 | 改什么 | 文件:行 | 做法 | 成本 |
|---|---|---|---|---|
| S1 | 入口补「年份/套数」 | `practice_setup_screen.dart:327-361`（写作/翻译弹层） | 在题型弹层后追加一层简单选择：「不限 / 2024 / 2023 / 2022 / 2021」+「第 1/2/3 套（可空）」；选中后传 `year:`；不选即维持现状 | 0.5 人日 |
| S2 | 抽出试卷身份（纯函数） | 新增于 `output_composer.dart` 工具区（`examLabelFor` 附近 `:795`） | `parsePaperMeta({String url, String hitTitle, String pageText})`：正则 `(20\d{2})\s*[年./-]\s*(\d{1,2})\s*月` + `第\s*([一二三四五六七八九十\d]+)\s*套` + `\bset\s*([1-9])\b`；**只有年+月命中才写月份，只有套号命中才写套**，都没命中就返回空 + 记 `siteHost` | 0.5 人日 + 单测 |
| S3 | 模型加字段 | `output_composer.dart:241-301` | `OutputSetSpec` 增 `int? paperYear` / `String paperLabel` / `String sourceSite`；`composeFromExam` 把 S2 结果填进去；title 改成 `'英语四级(CET-4) · 2023 年 12 月第 1 套 · 写作真题'`（`:1067`） | 0.2 人日 |
| S4 | 真落库 | `practice_setup_screen.dart:400-417` | 写 `paper_year`、`paper_label`（去掉 `:406` 的空串），`source` 保持 `exam`；单题仍写 `source_span`，**组级来源优先** | 0.1 人日 |
| S5 | 展示 | ①题库卡 `practice_history_screen.dart:230-239`；②答题页 `practice_flow_screen.dart:252-256`；③历史还原 `practice_history_screen.dart:85-93` | 统一一行「等级 · 年份套数 · 来源站点 · 校对状态」；答题页把「真题来源 · 已标注」升级为可解析的来源行（站点名 + `paper_label`）；`_open` 补 `paper*/licenseNote` | 0.5 人日 |

**合计 ≈ 1.8 人日，0 迁移，0 新依赖。** 单题级 URL 若一定要入库，需给 `exercise_items` 加 `source_url TEXT`
（dbVersion 22→23 + 备份白名单），**建议二期并请用户确认**（组级 `license_note` 已能回答"这题哪来的"）。

**风险与取舍**
- 抓取页里「年/月/套」常只出现在**页面标题**，S2 命中率估计 60~80%；未命中时只显示「来源站点 · 抓取于 X 月 X 日」，**绝不猜**（与现有"没来源不生成"纪律一致）。
- 模型侧继续**禁止**生成年份标签；试卷身份只来自 URL/页面文本，避免"AI 编造某年真题"。
- 若 S1 只给年份不给套数，title 可退化为 `2023 年 · 写作真题`，不影响其他链路。

---

## 二、P0-2「四六级混排」根因与分桶方案

### 2.1 现状（三层）

| 层 | 位置 | 事实 | 后果 |
|---|---|---|---|
| 目标层 | `lib/services/drill_catalog.dart:88-106` | 目标只有 `id: 'cet', label: '四六级'`（`:90-91`），没有独立「四级」「六级」 | 用户**根本无法表达**"我只练六级" |
| 映射层 A（真题） | `lib/services/output_source.dart:554-573` | `targetExamOf` 把「四六级」先记为 `cet4`（`:564-566`），只有明说"六级"才 `cet6` | 六级考生的真题题组也被标成 `cet4` |
| 映射层 B（材料/内置） | `lib/services/output_composer.dart:783-790` | `examTypeFromGoalIds` **只认英文 id**（`cet/cet4/cet6/…`）；中文标签「四六级」→ 落到 `:790` 返回 `'none'` | 材料出题的 `exam_type` 落 `none`（经 `composeFromMaterial:906`、`:979`），且提示词不带目标考试（`:932` 传 `examGoal: null`） |
| 素材层 | `lib/services/output_bank.dart:628-667` | 「四六级高频词」（`:630-636`）与「四六级作文题」（`:662-668`）是**四六级共用单池**，条目无考试标签；`EssayPrompt` 默认 rubric `cet4_writing`（`:109`） | 内置练习天然混排 |
| 唯一可分的资产 | `lib/services/exam_vocab.dart:26`、`:130-146`、`:197-209` | 词条带 `exams` 多标签（`cet4/cet6/…`），`ExamVocab.wordsFor('cet4'/'cet6')` **已实现** | 词汇其实能真正按 4/6 分桶，只是内置词池没用它 |
| 存储层 | `lib/services/database.dart:393`、`:2567-2597` | `exercise_sets.exam_type` 列存在；`listExerciseSets({examType, section, limit})` **已支持过滤** | 数据层已就绪 |
| 展示/入口层 | `practice_history_screen.dart:45`（只传 limit）、`:230-239`（不显示等级）；`practice_setup_screen.dart:446-448`（原生 AppBar，无筛选） | 查询不带筛选、界面不显示等级 | **混排现场**：题库列表里 CET-4/CET-6/考研全混 |

### 2.2 哪些能靠现有数据区分，哪些必须补

**能靠现有数据（修好映射 + 回填即可）**
1. `exam_vocab.json` 每条词的 `exams` 标签 → 词汇练习可真正分 `cet4` / `cet6`；
2. 题组 `license_note` 里的抓取 URL + 题组 title 里的「四级/六级/CET-4/CET-6」关键词 → 可做老数据回填；
3. `exercise_sets.exam_type` 已有值（真题路径虽然会把四六级记成 cet4，但「六级」字样在 title/URL 里能纠回来）；
4. `source` 枚举（`ai/builtin/user_import/exam`）→ 至少能把「真题」与「材料题」分开筛。

**必须补元数据 / 改语义（需要决策）**
1. 内置词池与作文池没有考试标签：要么改用 `ExamVocab.wordsFor(examId)`（推荐，一套口径），要么给 `OutputBank` 条目加 `exams` 字段；
2. 用户目标要能区分 4/6：拆 `DrillCatalog` 目标（`'cet4'/'cet6'`）会动 `LearnerModel.goals` 语义与目标选择 UI，**需用户确认**（建议保留「四六级」通用档 + 新增「四级」「六级」两档，已存数据不自动迁移）；
3. 老题组 `exam_type` 的 `none`/误标 `cet4` 回填（一次性脚本或"重建题库标签"按钮）。

### 2.3 分桶方案（增量两级，一期不改 DB）

**P1 · 入口筛选（0 语义改动）**
- 题库页顶部与四阶设置页顶部各加一行等级筛选：`全部 / CET-4 / CET-6 / 考研 / 雅思`
  （新组件 `V4LevelTabs`，视觉见渲染图 A/B）。
- 题库：`_load()` 传 `examType`（`practice_history_screen.dart:45` → `listExerciseSets(examType: _level)`），
  数据层直接生效（`database.dart:2577-2580`）。
- 新建：把当前筛选值写进 `exam_type`；真题路径直接传 `examType`；
  材料路径先修 `examTypeFromGoalIds`（见 P1.5）。
- 卡片 meta 显示等级标签（用 `examLabelFor` 的中文短名）。

**P1.5 · 统一映射 + 回填（0.7 人日）**
- 让 `examTypeFromGoalIds` 内部改用 `targetExamOf`（`output_source.dart:554`）实现，中文标签也能映射；
  一处实现替代两套口径（`output_composer.dart:783-790`）。
- 回填规则（只对 `source='exam'` 且 `paper_label` 为空的组）：title/URL 命中内联 `四级|CET-4` → `cet4`；
  `六级|CET-6` → `cet6`；「四六级/无标记」→ 保持 `none` 并标"待定级"，**不猜**。
- 旧组 UUID 不动，只 UPDATE 两列，风险低；建议做成设置页「重建题库标签」按钮而非隐式启动迁移。

**P2 · 目标层拆分（需用户确认，1.5~2 人日）**
- `DrillCatalog.goals` 增 `cet4` / `cet6`（label「四级」「六级」），`'四六级'` 保留为通用；
- 内置素材按等级切：词汇改用 `ExamVocab.wordsFor('cet4')`、`wordsFor('cet6')`；
  `OutputBank` 作文题按 `rubricId`（`cet4_writing`）与新增 `cet6_writing` rubric 分池；
- 兼容：已存 `goals` 含「四六级」时按通用处理，不自动改写用户数据。

---

## 三、输出链路现状审计（file:line）

> 结论先说：**13 个输出文件里，v4 组件只出现 1 次**（`output_home.dart:342` 的 `V4PillButton`）；
> `V4StageCard` 在 `lib/widgets/v4/v4_kit.dart:910` 定义好了，**lib 内 0 调用**（全库 grep 只有定义处）。
> 也就是说：输出板块是"**换了组件的皮，没换排版骨架**"——`AppBar + ListView + AppCard` 还是 v3 结构。

| 屏 | 文件:行 | 现状 | 判定 |
|---|---|---|---|
| 输出首页 | `output_home.dart:300-350`（自绘头区 + 练习中心胶囊 `:342`）、`:353-426`（方向卡）、`:429-431`（今日建议）、`:434-478`（GridView 2×2 四阶卡）、`:504-563`（ActionTile 链） | 唯一接了 v4 的屏，但四阶卡是 AppCard 版（`widgets/output_tier_card.dart:52-129`）：无阶位色、无进度环、图形只 40px | 半新半旧 |
| 四阶设置 | `practice_setup_screen.dart:446-448`（**原生 AppBar**）、`:453-493`（hero 引导卡）、`:524-540`（纯文字分组头）、`:713-825`（来源卡 + 真题卡） | 旧骨架；信息靠"一堆同构小卡"堆出来，没有来源/等级字段位置 | 旧样式 |
| 答题页 | `practice_flow_screen.dart:221-235`（原生 AppBar）、`:240-258`（文字进度行「第 N/M 题」）、`:262-333`（题面卡）、`:338-417`（作答卡 + 48 高 `FilledButton` `:392-407`）、`:418-459`（结果 + Material 按钮） | 无进度线、无等级/来源标注位、作答与提交都在同一张卡里 | 旧样式 |
| 批改结果 | `widgets/practice_result_view.dart:61`（**单张 AppCard 包全部**）、`:76-122`（`RadialGauge` 88）、`:130-184`（错误条 `errorContainer.withAlpha(60)` `:146`）、`:271-278`（维度 `LinearProgressIndicator`） | 总分/维度/错误/参考/总评全在一张卡里，缺"档位"视觉重音 | 旧样式 |
| 题库 | `practice_history_screen.dart:144-145`（AppBar「题库」）、`:155-178`（列表）、`:182-249`（卡片）、`:45`（**查询无筛选**） | 混排 + 无名卷子 | 旧样式 + P0 现场 |
| 练习中心/旧计划 | `drill_plan_screen.dart:746-757`（AppBar + 刷新）、`:758-793`（骨架/列表）、`:797-860`（radio 行） | 旧计划链路，保留 | 旧样式 |
| 写句三题型 | `sentence_practice_screen.dart:350-375`（build）、`:376-506`（改写）、`:507-631`（纠错）、`:632-780`（连词成句）、`:781-`（总结） | 每题各写一套行卡 | 同源不统一 |
| 语境选词 | `cloze_practice_screen.dart:126-136`（build）、`:137-238`（题目）、`:239-274`（句子）、`:275-318`（选项）、`:319-`（总结） | 同上 | 同源不统一 |
| 词表练习 | `word_bank_drill_screen.dart:147-157`（build）、`:158-269`（题目）、`:270-`（总结） | 同上 | 同源不统一 |
| 旧回译练习 | `exercise_screen.dart:53-…` | v2 遗留页，四阶链路已不走 | 只做同皮肤 |
| 输出侧阅读器 | `article_reader.dart:103-…` | 旧版阅读器 | 只做同皮肤 |

**共性问题（决定重做方向）**
1. 顶部全是 `AppBar`（Material 原生），与输入板块的果冻头图断层；
2. 信息层级只有「标题 16 / 正文 14.5 / 小字 11」三档，**缺 30~34 的页面主标 + 缺 10.5 的眉标**，所以每屏"看起来一样平"；
3. 卡片全部同构（`AppCard`），没有"身份色/阶位色/来源徽标"，四阶**视觉上不分阶**；
4. 没有"来源/等级/校对"这类**元信息带**，P0 的两个问题在 UI 上无处落。

---

## 四、两个视觉方向（同一屏，两种设计）

> 旗舰屏选 **「四阶设置 · 出题来源」**（P0 两个问题都落在这屏）+ **答题页**。
> 渲染图是**真组件真字体真图标**的 390×844 截图（3x → 1170×2532），见文末。

### 方向 A · 纸面工作台（Editorial）

**一句话主张**：输出是「做题 / 写长文 / 看批改」的专注场景，界面要像一张干净的练习纸——
**没有渐变、没有阴影，只有细边与编号**；主行动永远只有一个。

**设计语言**
- 底色：`#F6F6FD`（`V4Skin.pageBg`）；面：`#FFFFFF`；细边：`#E4E7F5`（`hairline`）
- 圆角：来源行/标签 16，题面/作答纸卡 20，胶囊 999；**不用 hero 32、不用阴影**
- 字阶：页面主标 30 / w900 / -0.9；区块头 16 / w800；卡标题 14.5 / w700；正文 13；元信息 11 / 10.5
- 颜色：主色 `#4C5AF0` 只给「编号 01/02、主按钮、等级选中」；其余全是 ink/inkSoft/inkFaint 的中性层级
- 动效：只在层级变化时动——换题 240ms 淡入上滑、提交后结果 420ms 入场、按压 0.98；不做循环动画
- 组件：`V4LevelTabs`（细边扁平胶囊）、`V4PaperRow`（白面+1px 边）、`V4SourceLine`（来源行）、`V4IndexHead`（编号区块头）

**四阶设置屏 · 线框**
```
┌───────────────────────────────────────────┐
│ ←              第 04 阶 · 写篇          ◷ │  ← 极细工具行（无 AppBar 底色）
│                                           │
│  选一份真题                                │  ← 30/w900
│  先按考试等级筛，题目都标到年份/套数/来源站点  │  ← 13 inkSoft
│  [全部] (CET-4) [CET-6] [考研] [雅思]      │  ← 选中=主色渐充实心
│                                           │
│  01 ── 推荐来源 ──────────────── 3 份      │  ← 编号 + 细线 + 计数
│  ┌───────────────────────────────────┐    │
│  │ ▢ 2023 年 12 月 四级真题 · 第 1 套  │    │  ← 白面/1px 边/无影
│  │   写作 · 3 题 · 中国教育考试网 · 待校对│    │
│  └───────────────────────────────────┘    │
│  ┌───────────────────────────────────┐    │
│  │ ▢ 2023 年 6 月 四级真题 · 第 2 套   │    │
│  └───────────────────────────────────┘    │
│  02 ── 我的题库 ──────────────── 18 组     │
│  · 2024 年 6 月 四级真题 · 第 1 套       › │  ← 只有细线，不给卡片
│  · 2023 年 12 月 六级真题 · 第 2 套      › │
├───────────────────────────────────────────┤
│ [ 从我的材料出题 ]      ( 开始练习 → )     │  ← 底部固定，唯一主行动
└───────────────────────────────────────────┘
```

**答题页 · 线框**
```
←   第 3 / 6 题  [CET-4]              ✕
━━━━━━━━━━━━━━━━━──────────────────────      ← 3px 进度线
写句 · 回译            来自 2023 年 12 月 第 1 套
┌───────────────────────────────────────────┐
│ 把这句话译回英文                            │
│ 他直到深夜才意识到自己忘了带钥匙。            │  ← 18/w700
│ [≥ 8 词] [语法 · 倒装] [待校对]             │
└───────────────────────────────────────────┘
┌───────────────────────────────────────────┐
│ 你的英文                                    │
│ 在这里写出你的英文句子…                      │  ← 白纸，112px
│ ─────────────────────────────────────     │
│ 📷   🖼                             0 词   │
└───────────────────────────────────────────┘
┌─ 🔗 本题来源 ──────────────────────────────┐
│   中国教育考试网 · 2023 年 12 月 · 第 1 套 · 写作  ↗ │
└───────────────────────────────────────────┘
┌─ 批改标准 ─────────────── CET-4 写作 rubric ┐
│  40 内容 ▬▬▬▬   40 语言 ▬▬▬▬   20 结构 ▬▬  │
└───────────────────────────────────────────┘
        ( 提交批改 )                          ← 底部唯一主行动
```

**与输入板块的连续性**：输入内页（材料中心/阅读器 v5）本来就是「白面卡 + 细边 + 大圆角」，
A 是同一套内页语言的外延；不引入新的颜色关系，只是把"果冻彩头图"留在入口屏。

**改动成本**：3~4 人日，6 个文件
`v4_kit.dart`（+`V4LevelTabs` / `V4PaperRow` / `V4SourceLine` / `V4IndexHead`，约 250 行）
`output_home.dart`、`practice_setup_screen.dart`、`practice_flow_screen.dart`、
`practice_history_screen.dart`、`practice_result_view.dart`。
**风险**：低。不动组件默认外观，只加新件；`theme_test` 的"裸色值"闸门好过（全走 skin 令牌）。

---

### 方向 B · 果冻阶梯（Jelly）

**一句话主张**：输出入口要和主屏一样「有色彩、有层次」——渐变头图 + 果冻来源卡 + 进度环；
进到答题内页再收敛成白纸。

**设计语言**
- 头图：`V4Skin.heroGradient`（`#EDEFFF → #FFF0EA`）叠最浅果冻色 + 两团光斑（主色 26% / 粉 24%），底部 32 圆角 + `heroShadow`
- 来源卡：`skin.pastelFill(i)` 四组果冻渐变 + `skin.shadow`（24/10 主色柔影）+ 白圆环 + 白胶囊 CTA
- 圆角：卡 26 / 头图 32 / 控件 16 / 胶囊 999；字阶同上但标题用 30、卡标题 15、眉标 10.5（字距 1.8）
- 动效：头图滚动收束（大标题→小标题、渐变淡出）240ms；来源卡按压 0.98；进度环一次 600ms 生长；尊重 `减少动态`
- 组件：`V4HeroHeader` 变体（`v4_kit.dart:95`）、`V4StageCard`（`:910`，**现成但没人用**）、`V4ProgressRing`、`V4GlassChip`

**四阶设置屏 · 线框**
```
╭───────────────────────────────────────────╮  ← 渐变头图 + 光斑
│ ←                              [ 练习中心 ] │
│  按真题练                                   │  ← 30/w900
│  2023 年 12 月 · 第 1 套 · 写作真题           │
│  (写作·3题) (来源已标注) (待人工校对)         │  ← 玻璃胶囊
╰───────────────────────────────────────────╯
   ⟮ 全部 │(CET-4)│ CET-6 │ 考研 ⟯            ← 白卡分段控件
  推荐真题                    按你的目标(CET-4)排序
  ╭───────────────────────────────────────────╮
  │ ◔66  2023 年 12 月 四级真题 · 第 1 套  (推荐▸)│ ← pastel 渐变卡 + 进度环
  │      写作 · 3 题 · 中国教育考试网 · 待校对    │
  ╰───────────────────────────────────────────╯
  ╭───────────────────────────────────────────╮
  │ ◔33  2023 年 6 月 四级真题 · 第 2 套    (开始▸)│
  ╰───────────────────────────────────────────╯
  我的题库                              18 组
  ╭───────────────────────────────────────────╮
  │ · 2024 年 6 月 四级真题 · 第 1 套        › │
  │ · 2023 年 12 月 六级真题 · 第 2 套       › │
  ╰───────────────────────────────────────────╯
        ( 开始练习 → )                          ← 渐变胶囊
```

**与输入板块的连续性**：最强——直接复用输入首页/我的的果冻头图关系与四组 pastel，
用户从输入切到输出不会有断层；`V4StageCard` 本来就是给四阶写的（`v4_kit.dart:909-1034`）。

**改动成本**：5~6 人日，7 个文件（多 `drill_plan_screen.dart` 与头图变体）；
**风险**：中。① 输出场景是长文写作/读批改，彩色卡+柔影在信息密集页容易喧宾夺主；
② 每屏头图+光斑+柔影对低端机的绘制成本（现有纪律是"一屏一两处模糊"）；
③ 答题/结果页若照搬果冻卡，会与"低干扰"目标冲突。

---

## 五、推荐

**推荐：以 A 为骨架，偷 B 的「入口屏头图」——即 A+ 混合。**

**理由**
1. 用户要"高级、精美、不喧宾夺主、有逼格"——输出链路的核心动作是**写长文、读批改**，这两件事最怕彩色噪声；
   A 的细边清单/白纸在答题与结果页最耐看，且和输入内页 v5 已经是同一语言（不是另起一套）。
2. 用户同时要求"内页与主屏同水准"——**入口屏**（输出首页/练习中心）可保留果冻头图+pastel 卡（B 的部分），
   **内页**（设置/答题/批改/题库）收敛到 A。这样"炫技在入口、专注在内页"，正好是 v4 美术方向写的"炫技但不喧宾夺主"。
3. 实现成本：A 3~4 人日 vs B 5~6 人日，且 A 不需要新动效/模糊，回归风险小；P0 两个问题在 A 上都能一次性落位。

**明确不推荐**：整条链路全 B。长文本 + 高密度评分信息下，果冻卡与柔影会持续抢注意力，
与"清晰的档位/依据"这一评分信息目标相冲。

---

## 六、落地顺序（每步先出图，再改生产代码）

| 步 | 屏 | 改动文件 | 内容 | 预估 |
|---|---|---|---|---|
| 1 | **四阶设置（旗舰）** | `practice_setup_screen.dart`、`v4_kit.dart`（+`V4LevelTabs`/`V4PaperRow`/`V4SourceLine`）、`output_composer.dart`（P0-1 S2/S3）、`practice_setup_screen.dart:400-417`（S4） | 换头区/等级筛选/来源标注/年份套数落库 | 1.5 人日 |
| 2 | **答题页** | `practice_flow_screen.dart`、`v4_kit.dart`（+`V4SourceLine`） | 进度线、等级标签、来源行、作答纸卡、底部唯一主行动 | 1 人日 |
| 3 | 批改结果 | `widgets/practice_result_view.dart` | 得分环 + 档位重音、维度条统一、错误条降噪（去掉 `withAlpha(60)` 的脏红） | 0.8 人日 |
| 4 | 题库 + 筛选 | `practice_history_screen.dart`、`database.dart`（不改结构，仅调用） | 等级筛选行、来源/年份 meta、空态 | 0.6 人日 |
| 5 | 输出首页 | `output_home.dart`、`widgets/output_tier_card.dart` | 四阶卡改用阶位色/进度环（复用 `V4StageCard`），入口屏保留果冻头图 | 0.8 人日 |
| 6 | 旧计划页/旧链路同皮肤 | `drill_plan_screen.dart`、`exercise_screen.dart`、`article_reader.dart` | 只换皮肤，不改逻辑 | 0.5 人日 |

**P0 修复与视觉可以并行**：S1~S5（来源）与 P1（等级筛选）都不依赖视觉方向，先做也不浪费。

---

## 七、渲染产出（真实渲染，假数据，不联网）

- 脚本：`test/output_preview_render_test.dart`
- 运行：`cd /d/readflow && flutter test test/output_preview_render_test.dart --no-pub`
- 出图（脚本会同时写两处，二选一归档即可）：

| 文件 | 内容 | 用来看什么 |
|---|---|---|
| `build/ui_real/output-preview-A.png`（同步 `docs/ui-preview/real/`） | 方向 A · 四阶设置（出题来源） | 纸面清单 + 等级筛选 + 来源标注 |
| `build/ui_real/output-preview-B.png`（同步 `docs/ui-preview/real/`） | 方向 B · 四阶设置（出题来源） | 渐变头图 + 果冻来源卡 + 分段控件 |
| `build/ui_real/output-preview-answer-A.png`（同步 `docs/ui-preview/real/`） | 方向 A · 答题页 | 来源行 + 等级标签 + rubric 预告 |

- 技术口径与既有渲染测试一致：加载 `C:/Windows/Fonts/NotoSansSC-VF.ttf` 与
  `D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`，
  390×844 逻辑屏，`RenderRepaintBoundary.toImage(pixelRatio: 3)` → 1170×2532。
- 两张同屏设计刻意做了结构差异（A：无渐变/无阴影/编号区块/扁平胶囊；B：渐变头图/光斑/果冻卡/进度环/白卡分段），
  不是"换个颜色"三连。

---

## 八、未完成 / 风险

1. **渲染测试尚未执行**：本会话 shell 命令卡死（Lead 已通告），需要 shell 恢复后串行代跑；
   若编译报错，按日志修（文件只依赖 `config/design_tokens|theme|v4_theme`、`widgets/graphics`、`widgets/v4/v4_kit` 的稳定 API）。
2. **年份/套数抽取未实测**：S2 的正则命中率需用真实抓取页跑一轮（建议打印命中/未命中样本各 20 条再定稿）。
3. **四六级拆目标需用户确认**：会改目标选择 UI 与 `LearnerModel.goals` 语义，本文只给方案不擅自定。
4. **单题级来源 URL** 若必须入库，需 `exercise_items` 加列 + 迁移 22→23 + 备份白名单，二期并需用户点头。
5. 本轮**未改任何 lib/ 生产代码、未 commit、未改 pubspec、未装依赖**。
