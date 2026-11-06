# 「找材料」重构方案(2026-11-06 · 待用户选型)

> 用户原话(本轮):
> 「把现在的『按我的需求找材料』改成**找材料**——点进去两部分:①自由搜 ②按个性化需求找
> (读取学习助理里统计的用户情况);两个子功能分别跳转独立的搜索 + 结果界面,UI 与升级后的材料中心一致。
> 先出方案 + 真实渲染图,我选完再实现。」
>
> 本文只做**方案与选型材料**,不改生产代码。6 张真实渲染图见 §6。
> 状态:方案稿 / 待选型。仓库 `D:\readflow`,基线 master 380d2d1 + task-3 频道页改造中间态。

---

## 0. 一句话结论

「找材料」应该是一个**两入口的壳页**:入口页只做"选路",真正干活的是两个**独立的搜索页/结果页**;
两个结果页**共用同一套结果渲染**(类型分组 + 每页 10 条真分页 + 「有真封面才显示封面」文字版式 +
保存到我的 + 打开原文),因此视觉和升级后的频道页天然一致,不做第二套设计语言。

- **推荐 B(上下分区)**:点进来第一眼就是搜索框,下面直接是"按你的情况找"的数据面板 → 点击最少、数据摆得最明。
- A(并列大卡)视觉最"高级/仪式感",但每个动作多一次点击;C(工作台式)信息密度最高,但与结果页/频道页的筛选三处重复,最贵。

---

## 1. 现状审计(为什么会觉得"入口和页面对不上")

### 1.1 现在的入口链路:名字叫「按需求找材料」,但点进去是"频道页 + 一个只读摘要条"

| 现状 | 位置(file:line) | 说明 |
|---|---|---|
| 材料中心首页的卡片 | `lib/screens/input/material_hub/material_hub_home_view.dart:624-679` | `_needCard()`:标题写死 `'按需求找材料'`(:655),副标题是需求摘要 `widget.need.summary`(:662),整卡 onTap → `onOpenNeed`(:627) |
| 同一入口的空态胶囊 | 同上 `:240` | 今日精读空态里的 `_pill('按需求找材料')`,同一个 `onOpenNeed` |
| 接线 | `lib/screens/input/material_center_screen.dart:317` | `onOpenNeed: () => _openDirection(MaterialTaxonomy.need)` |
| 跳转 | `material_center_screen.dart:228-240` | 统一 push `MaterialChannelScreen(direction: def.id)`;注释(:228-231)明确:旧的 `MaterialBrowseScreen` 只剩"去设置需求"一个用途 |
| 频道页的"按需求"分支 | `lib/screens/input/material_channel_screen.dart` 的 `_channelHeaderBar`(task-3 中间态 `:1520`)、`_needSummaryBar`(`:1657`) | `direction == need` 时显示**只读需求摘要 + 「去设置需求」文字按钮**,不在本页编辑 |
| 去设置需求 | `_openNeedSettings()`(task-3 中间态 `:1393`) | push `MaterialBrowseScreen(direction: need)` |
| 旧「按需求找材料」页 | `lib/screens/input/material_browse_screen.dart:23-35`(类), `:316-379`(`_needEditor`) | 难度档 + 目标(只读)+ 形式 chips + 「保存需求并查看结果」(:154-167);保存写 `MaterialPrefs`(:103-113);结果列表按 `MaterialNeed.rank` 排序(:56-73) |
| AI 版旧页(另一条腿) | `lib/screens/input/material_discover_screen.dart:23`(职责注释), `:248`(AppBar 标题**就是**「按我的需求找材料」), `:427`(补充需求输入框) | 由 `material_browse_screen.dart:243-253` 的"AI 补长尾"卡进入 |

**结论(关键事实)**:
1. 用户看到的「按我的需求找材料」字样,只存在于**AI 旧页的 AppBar**(`material_discover_screen.dart:248`)和材料中心卡片的**近似文案**(`material_hub_home_view.dart:655`)。这两个是**两条不同的链路**,一条通向频道页、一条通向 AI 检索页 —— 名字相同、页面不同,正是"盲盒"感的来源之一。
2. 现在**没有任何"自由搜"入口**:公开源检索能力(`OriginalSearch.search`)只被旧分类页/分类 AI 页调用(`category_material_screen.dart:167`、`material_category_screen.dart:75`),材料中心首页没有搜索框。
3. 频道页顶部是**只读需求摘要**,要改需求得再跳一次旧页;用户点进来想看"按我的情况找"却看到一屏"发现/我的"频道内容 —— 认知断层。

### 1.2 旧三页各自的职责(要合并成"两部分",先划清谁留谁废)

| 页面 | 当前职责 | 本轮处理建议 |
|---|---|---|
| `material_center_screen.dart`(材料中心首页) | 今日精读 / 按需求 / 按题材 / 按形式 / 按场景 / 材料库 | **不动主体**;只把「按需求找材料」卡片换成「找材料」入口(指向新壳页),其余四个方向仍走频道页 |
| `material_browse_screen.dart`(旧按需求页) | 需求编辑(难度/目标/形式)+ 保存 + 结果列表 + AI 补长尾 | 需求编辑能力**并入"按需找"页的"调整需求"**;本页可降级为纯设置页或删除 |
| `material_discover_screen.dart`(AI 旧页) | 需 求→ AI 计划 → 公开源+官方搜索 → 补抓正文 → 展示 | 与频道页 `_startDiscovery` 能力重叠(`material_channel_screen.dart` `:786+`),**不建议再保留第二条 AI 链路** |
| `material_channel_screen.dart`(频道页) | 发现(真实检索 + 快照 + 分组 + 分页)/ 我的(可管理) | **作为两个新搜索页的结果页底座复用**(见 §5) |

### 1.3 「学习助理里统计的用户情况」到底能读到什么(全部真实,不编)

**总入口(推荐新页直接调它)**:`TutorSnapshotService.load()` → `TutorDashboard`,
`lib/services/tutor_snapshot.dart:73-104`(加载)、`:25-64`(值对象字段:`snapshot`/`prefs`/`source`/`insights`/`suggestions`/`review`/`reviewStats`/`outputStats`)。
它已经把"快照 + 偏好 + 输出聚合 + 任务复盘"四路拼好,**每块失败都降级**(`:69-72` 注释)。

| 面板要显示的东西 | 真实字段(能读到) | file:line |
|---|---|---|
| 词汇量基线 / 是否测过 | `LearnerModel.vocabEstimate` / `vocabLow` / `vocabHigh` / `lastPlacementAt`;`LearnerContext.describeBaseline(model)` 直接产出一句人话 | `lib/models/learner_model.dart:93-108`;`lib/services/learner_context.dart:41-59` |
| 有效词汇量(i+1 计算用的"已知词") | `LearnerContext.effectiveVocab(model)` + `knownWords(...)` | `learner_context.dart:27-33`、`:65-90` |
| 难度档 i+1 / i+10 / i+100 | `MaterialNeed.load()` → `need.band`;档位定义与区间 | `lib/services/material_need.dart:34-48`;`lib/services/material_prefs.dart:48-111` |
| 学习目标(多选) | `LearnerModel.goals`(主目标 `goal` 兼容旧数据)→ `InputPreferences.examGoals` | `learner_model.dart:106-113`;`lib/services/input_prefs.dart:462-467`、`:537` |
| 兴趣题材 | `LearnerModel.interests` ∪ `MaterialPrefs.genres` → `InputPreferences.interests` | `learner_model.dart:122-123`;`input_prefs.dart:466-467`、`:538` |
| 弱项(语法错误) | `TutorDashboard.source.errorTagCounts`;快照里已筛好的 `weakGrammarTags`(active、按次数倒序、最多 3 个) | `tutor_snapshot.dart:118-132`、`:175-196`;`lib/services/learner_snapshot_loader.dart:109-121` |
| 阅读速度 | 实测 wpm(`extras['reading_wpm']`)优先,否则默认 200 | `learner_context.dart:93-98`;`learner_snapshot_loader.dart` 的 `snapshot.avgWpm` |
| 近 30 天读完 / 在读 | `DatabaseService.getReadingStats(days:)` + `getRecentMaterials(limit:)`;`TutorDashboard` 里已折算成 `materialsFinished30d` / `materialsReading` | `learner_snapshot_loader.dart:56-65`;`tutor_snapshot.dart:134-154`、`:184-185` |
| 每日可投入分钟数 | `LearnerModel.dailyMinutes` → `InputPreferences.dailyMinutes` | `learner_model.dart:115-116`;`input_prefs.dart:487-488` |
| 屏蔽题材 / 屏蔽关键词 | `LearnerModel.blockedTopics` / `blockedKeywords` | `learner_model.dart:125-129`;`input_prefs.dart:481-485` |
| "要不要调档"的真实建议 | `loadBandAdvice()`(读完率 / 每百词查词数 / 读后测验正确率,三信号至少 2 个才给) | `input_prefs.dart:412-436`;信号 `:269-292`;建议值对象 `:295-317` |
| 五维现状(可直接当"依据"文案) | `buildTutorInsights(source)` → `TutorInsight.title/valueText/evidence/measured/severity` | `lib/services/tutor_insights.dart:299`(生成)、`:197-244`(字段) |
| 搜索历史(自由搜"上次搜过") | `MaterialPrefs.lastQueryFor(category)` / `rememberQuery(category, query)` | `lib/services/material_prefs.dart:393-406`、`:408-426` |

**诚实边界(必须写进界面,不许装)**:
- `TutorInsight.measured == false` 时约定 `valueText` 固定「待测」且 evidence 里**不许出现统计数字**(`tutor_insights.dart:199-203`)。找材料面板必须沿用这条纪律:没数据就显示"待测 + 去测一次词汇量",不编。
- 复习留存率目前没有现成聚合口径,`tutor_snapshot.dart:180-181` 明确传 `null` —— 面板不要展示"留存率"。
- 公开源全部是英文源(`MaterialSource.language` 默认 `'en'`,`material_source.dart:59-60`;`sources` 列表 `:265-351`),所以"语言"筛选**只能如实写"英文(当前公开源)"**,不能给一个点了没用的多语言下拉。

### 1.4 结果页现有能力(新页要复用的"与频道页一致"的 5 个要素)

| 要素 | 现成实现 | file:line |
|---|---|---|
| ① 类型分组(教材/真题/书籍/论文/外刊/文章/其他) | `_groupOrder` / `_groupLabels` / `_groupKeyOf` / `_groupedResults()` / `_groupHeader()` | `material_channel_screen.dart` 的 `_groupHeader()`(中间态 `:2229`)、`_groupOrder`(`:2707`)、`_groupLabels`(`:2718`)、`_groupedResults()`(约 `:2260`) |
| ② 真分页(每页 10 条 + 页码控件) | `materialChannelPageSize = 10`、`materialChannelPageCount/Clamp/Range` 四个纯函数;`_page` 状态 + 切页滚回顶部 | `material_channel_screen.dart:118-152`、`:320-321`、`:427-433` |
| ③ 封面规则(有真图才显示,没有给文字版式) | 频道页注释纪律 + `TextCover` 文字版式 + `coverHasImage` 判据 + `coverFor` 统一取图顺序 | `material_channel_screen.dart:53-54`;`lib/widgets/shelf_cover_grid.dart:29`、`:40-60`;`lib/widgets/material_cover.dart:225`;`lib/services/material_source.dart:505-528` |
| ④ 保存到我的 | 发现卡 → 补抓正文 → 入库 → 记保存关系;`MaterialChannelStore.addSavedMaterial` | `material_channel_screen.dart` `_ingestToLibrary`(中间态 `:1061`)/ `_saveToMine`(`:1116`);`lib/services/material_channel.dart:324-347` |
| ⑤ 打开原文 | `_openOriginal()` → `launchExternalUrl` | `material_channel_screen.dart` `_openOriginal`(`:1164`);`lib/services/external_link.dart` |
| 结果快照(下次进来先看到上次结果) | `MaterialChannelStore.saveRun/loadSnapshot`(按 channel id 存 9 字段摘要,append 去重、上限 120) | `lib/services/material_channel.dart:203-215`、`:232-310` |
| 检索过程时间线 | `SearchEvent` + `SearchTimeline` | `lib/services/original_search.dart:60-100`;`material_channel_screen.dart` `_processCard` |
### 1.5 要解决的 6 个差距

1. 「按我的需求找材料」这个名字**跨两条链路,含义不一致** → 统一成「找材料」壳 + 两个明确子入口。
2. **没有自由搜入口**(材料中心首页无搜索框,公开源检索能力闲置)。
3. 「按需求」入口点进去看到的是**频道页的只读摘要**,不是"按我的情况找"的动作页。
4. 需求编辑藏在旧页(`material_browse_screen.dart`),与"找"分离,一次操作要跨两页。
5. 个性化只用到了 `band + kinds + goals + extra`(`material_need.dart:16-31`),**学习助理的弱项/阅读速度/读完率/屏蔽项完全没用上**。
6. 结果页旧逻辑是"显示更多"无限追加(改造前 `_visibleCount += 10`),与频道页正在做的**真分页**不一致 —— 新页必须直接按分页口径写。

---

## 2. 三个方向(结构互不相同,不是换文案)

> 三个方向**共用**同一套"内部":`FindNeedContext`(读学习助理)+ `MaterialResultList`(分组/分页/封面/保存/原文)。
> 差别只在**入口页的第一屏结构**、**自由搜的入口形态**、**按需找面板的展开方式**,以及**结果页的信息层级**。

### 方向 A · 并列大卡(两张等宽大卡,各进各的独立页)

**一句话主张**:「找材料」是一张"岔路口",把两种找法做成两张同等重要的大卡,像两个 App 入口。

**首屏结构(390×844)**

```
┌ 找材料                                  [历史] ┐
│                                                │
│  找材料                                         │  ← 34px w900
│  两条路:自己搜,或者让软件按你的情况找。            │
│                                                │
│  ┌──────────────┐   ┌──────────────┐          │
│  │ [🔍]          │   │ [✨]          │          │
│  │ 自由搜        │   │ 按我的情况找   │          │
│  │ 输关键词,直接  │   │ 读学习助理的   │          │
│  │ 搜公开源原文  │   │ 统计:水平/目标 │          │
│  │ ·关键词 ·来源 │   │ i+10 四六级    │          │
│  │ ·类型 ·难度   │   │ 时态薄弱       │          │
│  │ 上次搜过      │   │ 基线           │          │
│  │ climate change│   │ 已掌握 4,200 词│          │
│  │ 去搜 →        │   │ 按情况找 →     │          │
│  └──────────────┘   └──────────────┘          │
│                                                │
│  最近搜过                   搜索历史 · 可清空    │
│  [新概念英语] [climate change] [四六级真题]      │
│                                                │
│  ┌ 上次找的结果还在 · 3 组 18 篇 · 2 分钟前 ┐    │
│  └ 继续看 →                              ┘    │
└────────────────────────────────────────────────┘
```

- **自由搜入口**:一张大卡 → 点卡进 `FreeSearchScreen`(独立页:搜索框 + 筛选 + 结果)。
- **按需找入口**:另一张大卡 → 点卡进 `NeedSearchScreen`(独立页:依据面板 + 找 + 结果)。
- **首屏职责**:只做"选路";卡片里放**最关键的 2~3 个真实值**("上次搜过" `MaterialPrefs.lastQueryFor`;`i+10` / `四六级` / 基线词数)。

**自由搜的输入与筛选(进页后)**

- 输入:单行搜索框,回车即搜;空关键词时给"推荐检索"(复用 `OriginalSearch.defaultQueryFor`,`original_search.dart:142-147`)。
- 筛选(全部真实可落地):
  - **来源**:`MaterialSourceService.sources` 9 个源(`material_source.dart:265-351`),五个标"实测可用"(`:371-383`)。
  - **类型**:`kind`(book / paper / news / podcast / wiki),与 `MaterialTaxonomy.form` 的 kinds 对齐(`material_taxonomy.dart:112-126`)。
  - **难度**:`MaterialBand` 四档(`material_prefs.dart:48-111`)—— 注意:自由搜的难度只能**在补抓正文后**按真实覆盖率算(`LearnerContext.difficultyHint`,`learner_context.dart:102-107`),未抓前不标难度(不许用来源猜)。
  - **场景**:`MaterialTaxonomy.scene` 的 `queries`(`material_taxonomy.dart:129-154`)。
  - **语言**:只有"英文",作为**说明文字**展示(见 §1.3 诚实边界)。
- 搜索执行:`OriginalSearch.search(query, category:, sourceIds:, onProgress:)`(`original_search.dart:156-277`),中文关键词会得到明确提示(`:181-186`)。

**按需找的个性化面板(读哪些真实字段 + 怎么展示"为什么推这些")**

- 面板 4 行 + 1 段解释:
  - `难度档`:i+10 · 挑战(来源 `MaterialNeed.band` / `MaterialPrefs.band`)
  - `学习目标`:四六级 · 兴趣阅读(来源 `InputPreferences.examGoals`)
  - `弱项`:语法:时态 8 次 · 冠词 5 次(来源 `TutorDashboard.source.errorTagCounts` / `weakGrammarTags`)
  - `最近阅读`:近 30 天读完 4 篇 · 180 词/分(来源 `TutorDashboard` 的 `materialsFinished30d` + `LearnerContext.wpmFor`)
  - `为什么推这些` 一行文案:模板在 §3.3 给出,每个括号都能指回上表某一行。
- 数据缺失时:该行显示「待测 · 去测一次(5 分钟)」,不显示数字。

**结果页(与频道页一致)**

- 结果页 = 频道页结果列表的复用件:**类型分组 → 组内每页 10 条 → 底部页码控件 → 每卡「开始读 / 保存到我的 / 打开原文」**;卡面**只在有 `imageUrl`/`coverUrl` 时画图,否则「标题 + 中文标题 + 来源/类型/难度」文字版式**。
- 结果页顶部固定一条"这次按什么找的"条件条(可"改条件"回入口),下面是结果;跑完一轮自动收起搜索过程(复用 `_processCard` 折叠模式)。

**跳转与返回**

```
材料中心首页 ──(按需求卡改名「找材料」)──▶ 找材料(A 大卡)
                                            ├─ 自由搜 ──▶ FreeSearchScreen ──▶ 结果(同页)
                                            └─ 按情况找 ─▶ NeedSearchScreen ─▶ 结果(同页)
返回:结果页返回 → 入口页(保留上次搜索词/上次结果);入口页返回 → 材料中心
```

**改动文件与成本**

| 文件 | 改动 |
|---|---|
| `lib/screens/input/find_material_screen.dart`(新) | A 版首屏:两张并列大卡 |
| `lib/screens/input/free_search_screen.dart`(新) | 搜索 + 筛选 + 结果(嵌共享结果件) |
| `lib/screens/input/need_search_screen.dart`(新) | 依据面板 + 找 + 结果(嵌共享结果件) |
| `lib/widgets/material_result_list.dart`(新,三方向都要) | 从频道页抽出分组/分页/卡片,频道页改为调用 |
| `lib/services/find_need_context.dart`(新) | 读学习助理 + 偏好,产"依据"数据 |
| `material_hub_home_view.dart` / `material_center_screen.dart` | 卡片改名 + 接线(`:624-679`、`:317`) |

成本:**1.5~2 人日**(不含 task-3 抽公共件的成本;若 task-3 不抽,则每方向 +0.5 日复制风险)。

**风险**:①两次点击才能搜,重度搜索用户会烦;②两张卡信息量有限,"最近搜过"只能塞 3 个 chip;③按需找数据全空时(新用户)右卡像"占位"。

---

### 方向 B · 上下分区(上:整条搜索框;下:学习助理数据面板)— 推荐

**一句话主张**:「找材料」= 一个搜索框 + 一张"你的情况"卡:想搜就点搜索框,想被安排就点下面的大按钮;一屏说清两件事。

**首屏结构(390×844)**

```
┌ 找材料                                  [历史] ┐
│  找材料                                         │
│  先搜,或者按学习助理给的情况找。                  │
│                                                │
│  ┌────────────────────────────────────────┐   │
│  │ 🔍 搜关键词,如 新概念英语 / climate change │ ⚙ │  ← 点一下 → 独立搜索页
│  └────────────────────────────────────────┘   │
│                                                │
│  ───────────────── 或 ─────────────────        │
│                                                │
│  按你的情况找        [实时读取]      学习助理 >   │
│  ┌────────────────────────────────────────┐   │
│  │ [🎚] 难度档   i+10 · 挑战(每100词2~10个) │   │
│  │ ─────────────────────────────────────  │   │
│  │ [🚩] 学习目标  四六级 · 兴趣阅读          │   │
│  │ ─────────────────────────────────────  │   │
│  │ [⚠] 弱项     语法:时态 8 次 · 冠词 5 次  │   │
│  │ ─────────────────────────────────────  │   │
│  │ [📖] 最近阅读  近30天读完 4 篇 · 180 词/分│   │
│  │ ┌ 为什么推这些 ──────────────────────┐  │   │
│  │ │ 按 i+10 + 四六级目标,优先长难句多、 │  │   │
│  │ │ 题材贴近考试的原文;语法弱项「时态」  │  │   │
│  │ │ 会在阅读里标出来。已避开:影视娱乐。  │  │   │
│  │ └────────────────────────────────┘  │   │
│  └────────────────────────────────────────┘   │
│  [      ✨ 按这些条件找材料      ]              │
│  [ 调整需求 ]            [ 看数据依据 ]         │
└────────────────────────────────────────────────┘
```

- **自由搜入口**:顶部那条"看起来能输入"的搜索框 —— **点一下直接 push 独立搜索页,不在本页就地输入**(避免两套输入状态;图 §6 的 `-B-entry.png` 就是这一态)。
- **按需找入口**:下面那张数据面板 + 一个全宽主按钮。
- 顺序理由:用户 80% 的"找材料"是"我心里有个词";搜索框必须在第一屏第一个可点元素。

**自由搜的输入与筛选**:与 A 相同(§2.A 的自由搜小节);差别是**进页时把入口页的搜索历史预填进去**(`MaterialPrefs.lastQueryFor`),空态给"最近搜过" chips。

**按需找的个性化面板**:4 行 + `为什么推这些` + 屏蔽项提示(见 §3 的字段表与文案模板)。
额外一条 B 独有设计:面板右上角挂 **`实时读取` 小徽标** —— 明示"这些不是写死的,是读你学习助理的";点「看数据依据」展开 5 维现状(`TutorInsight.evidence` 原文,evidence 字段本来就带数字和来源,`tutor_insights.dart:215-217`)。

**结果页(与频道页一致)**:与 A 相同底座,但结果页多一张**"依据卡"**(顶部):
`这次按什么找的:i+10 难度档 / 四六级 / 语法·时态薄弱 / 近30天读完4篇 / 已避开 影视娱乐`,右侧「改条件」回入口。
每张结果卡多一行**"为什么推"**(只在能说出真实依据时出现,见 §3.2 的两级严格降级)。

**跳转与返回**

```
材料中心 ──「找材料」──▶ 找材料(B 上下分区)
                          ├─ 点搜索框 ──▶ FreeSearchScreen(独立:搜索+筛选+结果)
                          └─ 按这些条件找 ─▶ NeedSearchScreen(独立:依据卡+结果)
返回:搜索页返回 → 入口页(搜索框显示上次词);结果页返回 → 搜索页(保留结果与页码)
```

**改动文件与成本**:同 A 的文件清单(首屏换结构)。成本 **2~2.5 人日**。
**风险**:①首屏偏长(搜索框 + 4 行面板 + 双按钮),小屏(360×640)要保证主按钮在第一屏内 → 面板在窄屏折叠成 2 行摘要 + "展开全部";②搜索框"像输入框但是按钮",必须写清文案(如占位符右侧放 `>` 或"点一下搜索"),否则用户会怼着输入;③面板行数多时"为什么推这些"会被挤到第二屏。

---

### 方向 C · 工作台式(模式切换 + 数据条 + 筛选台 + 单一主行动)

**一句话主张**:「找材料」是一个"选材控制台":顶上切模式,中间一屏看数据与条件,下面一个按钮开工;筛选像仪表盘一样常驻可扫。

**首屏结构(390×844)**

```
┌ ‹  找材料                                   [▤] ┐
│  ┌───────────┬───────────┐                     │
│  │  自由搜    │  按需找 ✓  │   ← 模式切换(点另一个也进独立页)│
│  └───────────┴───────────┘                     │
│  ┌ 4,200 ┐ ┌ 4 篇 ┐ ┌ 时态 ┐                   │  ← 学习助理三项硬数据
│  │已掌握词│ │近30天 │ │最弱语法│                  │
│  └───────┘ └──────┘ └──────┘                   │
│  ┌────────────────────────────────────────┐   │
│  │ 难度  [i+1] [i+10✓] [i+100] [不限]      │   │
│  │ 来源  [全部] [公版书] [外刊✓] [论文]     │   │
│  │ 类型  [教材] [真题] [文章]               │   │
│  │ 场景  [应试✓] [出国] [生活] [工作]       │   │
│  │ 语言  [英文]                            │   │
│  └────────────────────────────────────────┘   │
│  [        ✨ 按这些条件找        ]              │
│  [ 清空筛选 ]        [ 改需求量 ]               │
│  ┌ 上次结果:3 组 · 18 篇 · 2 分钟前 · 回到上次 ┐ │
└────────────────────────────────────────────────┘
```

- **两个子功能怎么呈现**:同一个页的**两个模式**;左侧分段控件切换,**任一模式点主按钮都进独立结果页**(独立页里才放搜索框/结果)。
- **自由搜的输入与筛选**:模式切到"自由搜"时,面板换成"搜索框 + 来源/类型/难度"三行,主按钮变"开始搜";结果页同 A/B。
  这是 C 的结构性代价:**搜索框在第二屏(模式切换之后)**,与 B 正相反。

**按需找的个性化面板**:不叫"面板",叫**数据条 + 筛选台**:三项硬数据(词汇量 / 近 30 天读完 / 最弱语法)+ 5 行筛选(难度/来源/类型/场景/语言),每行都预选画像值(难度=i+10、场景=应试、来源=外刊)。"为什么推这些"移到结果页顶部(与 B 相同),入口页只给"数据 → 条件"的映射感。

**结果页(与频道页一致)**:同 B 的依据卡 + 分组 + 真分页;C 独有:
- 结果卡改为**编号密排行**(01/02/03…,每行 56~68px),右侧两个图标位(保存/打开原文);
- **底部固定动作条**:`‹ 第 1/2 页 › · 继续找更多`(像控制台底栏,不滚走);
- 顶部右侧「筛选 3」胶囊,点开是半屏筛选面板(与入口页筛选台同源组件)。

**跳转与返回**

```
材料中心 ──「找材料」──▶ 找材料(C 工作台,默认「按需找」模式)
                          ├─ 切「自由搜」+ 开始搜 ─▶ FreeSearchScreen(独立)
                          └─ 按这些条件找 ────────▶ NeedSearchScreen(独立,密排+底栏)
返回:结果页 → 工作台(保留条件);工作台 → 材料中心
```

**改动文件与成本**:与 A 同文件清单 + 额外「半屏筛选面板」「模式状态持久化(上次模式)」;成本 **3~4 人日**(最贵)。
**风险**:①**三处筛选重复**(入口筛选台 / 结果页筛选 / 频道页 chips),将来改一处漏一处;②手机上"左侧栏→筛选台"信息密度高但不是真工作台,窄屏容易挤;③模式切换 vs 独立页,层级感最容易让人问"我现在在哪一层";④编号密排与频道页现有卡片样式差得最远(虽然要素一致,但视觉要再对一次)。

---

## 3. 三个方向共用的规格(选哪个都按这套实现)

### 3.1 「按需找」的依据数据 → 展示行(每行都能指回真实字段)

| 展示行 | 值(示例) | 真实来源(file:line) |
|---|---|---|
| 难度档 | `i+10 · 挑战(每 100 词 2~10 个生词)` | `material_need.dart:34-48` + `material_prefs.dart:48-111` |
| 学习目标 | `四六级 · 兴趣阅读` | `input_prefs.dart:462-467`(← `LearnerModel.goals`,`learner_model.dart:113`) |
| 弱项 | `语法:时态 8 次 · 冠词 5 次` | `tutor_snapshot.dart:118-132`(errorCounts)/ `learner_snapshot_loader.dart:109-121` |
| 最近阅读 | `近 30 天读完 4 篇 · 180 词/分` | `tutor_snapshot.dart:134-154`、`:184-185`;`learner_context.dart:93-98` |
| (辅助)基线 | `已掌握 4,200 词(词汇量测试)` | `learner_context.dart:41-59` |
| (辅助)已避开 | `影视娱乐、八卦` | `learner_model.dart:125-129`(blockedTopics/blockedKeywords) |
| (辅助)今日可投入 | `每天 20 分钟` | `learner_model.dart:115-116` |

### 3.2 「为什么推这些」文案模板(严格两级,不编)

**级别 1 · 搜索前(面板级,只用画像 + 需求字段)**:

> 按 **{band.label}** 档 + **{goals 前两个}** 目标,优先找{难度描述来自 `MaterialBand.hintForAi` / `band.description`}的原文;
> {if 弱项:语法弱项「{tag}」会在阅读里标出来};
> {if 屏蔽项:已避开你屏蔽的 {blockedTopics 前两个}}。

**级别 2 · 候选级(必须补抓到正文、算完覆盖率才允许出现)**:

> 为什么推:**难度 {覆盖率}%** 落在你选的 {band.label} · 命中目标「{goal}」 · {if 类型=真题/教材:官方搜索抓到原文}

> 硬约束:快照里没有 `analysis`(`material_channel_screen.dart` `_ChannelItem.analysis`,补抓后才有)时**不显示级别 2**,只显示来源/类型/权威度。这条和 `tutor_insights.dart:199-203` "没数据不许出现数字"是同一条纪律。

### 3.3 「自由搜」的筛选规格(能落地才摆出来)

| 筛选项 | 取值 | 落地方式(真实) |
|---|---|---|
| 关键词 | 任意 | `OriginalSearch.search(query, ...)`(`original_search.dart:156`);中文关键词由它自己提示"只认英文"(`:181-186`) |
| 来源 | 9 个源(`bbc_le/voa_le/npr/ted/gutenberg/wikipedia/arxiv/nasa/sciencedaily`) | `sourceIds` 参数(`:156-177`);五个"实测可用"(`:371-383`) |
| 类型 | book/paper/news/podcast/wiki | `sourcesForCategory`(`:134-139`)+ `MaterialTaxonomy.form` kinds(`material_taxonomy.dart:112-126`) |
| 难度 | i+1/i+10/i+100/不限 | 排序用 `MaterialNeed.rank`(`material_need.dart:71-76`);**标难度**要等补抓后按覆盖率(`learner_context.dart:102-107`) |
| 场景 | 应试/出国旅游/生活聊天/生产力英语 | `MaterialTaxonomy.scene` 的 `queries`(`material_taxonomy.dart:129-154`) |
| 语言 | 英文 | 如实标注(公开源全为英文,`material_source.dart:59-60`、`:265-351`) |

### 3.4 两个结果页的布局契约(与升级后频道页一致)

```
[返回] [搜索框/条件摘要]              [筛选 · n]
──────────────────────────────────────────────
依据卡(A 无 / B 有 / C 有):这次按什么找的:条件 chips… [改条件]
结果元信息:12 篇 · 2 组 · 第 1/2 页 · 官方搜索约 ¥0.012
── 组头:教材 · 课本 ──────────────────────────
[卡] 标题(2 行) / 中文标题 / 来源 · 类型 · 难度 / 摘要(2 行)
     [开始读] [保存到我的]            打开原文 ↗
     (若无真实封面:以上文字版式;有封面:左侧/顶部真图,文字在右)
── 组头:应试真题 ─────────────────────────────
[卡] …                                          (组内每页最多 10 条)
──────────────────────────────────────────────
      ‹ 上一页    第 1 / 2 页    下一页 ›
      [ 继续找更多(追加,页数增加) ]
```

- 分组顺序与组名固定:`_groupOrder` / `_groupLabels` / `_groupedResults()`(task-3 中间态 `:2707` / `:2718` / 约 `:2260`;收尾后复核)。
- 每页 10 条:`materialChannelPageSize`(`:118`);切页滚回列表顶(频道页已实现,`:427-433` 逻辑,新页照抄)。
- 封面:只有 `coverHasImage(url)`(`material_cover.dart:225`)为真才画图;否则用 `TextCover`(`shelf_cover_grid.dart:40-60`)文字版式。取图统一走 `MaterialSourceService.coverFor`(`material_source.dart:516-528`)。
- 「继续找更多」= `MaterialDiscovery.discover(extraQueries:, excludeUrls:)`(`material_channel_screen.dart` `:786+` 调用点),补抓正文入库(`_ingestToLibrary`)、保存关系 `MaterialChannelStore.addSavedMaterial`(`material_channel.dart:336`)。

---

## 4. 三方向对比(一句话)

| | A 并列大卡 | B 上下分区(推荐) | C 工作台式 |
|---|---|---|---|
| 一句话 | 岔路口:两张等宽大卡,各进各的页 | 先搜,或者按你的情况找(搜索框 + 数据面板) | 选材控制台:模式 + 数据条 + 筛选台 + 一个按钮 |
| 自由搜点击成本 | 2 次(卡→页→输入) | **1 次**(点搜索框即进页) | 1~2 次(先进模式) |
| "学习助理数据"可见度 | 卡内 3 个 chip | **4 行 + 为什么推这些** | 3 项数据条 + 预选筛选 |
| 首屏信息密度 | 中(大字大卡) | 中高 | **高** |
| 与频道页视觉一致性 | 高 | **最高**(结果页直接复用) | 中(密排+底栏是新形态) |
| 三处筛选重复风险 | 低 | 低 | **高** |
| 成本 | 1.5~2 人日 | 2~2.5 人日 | 3~4 人日 |
| 最大风险 | 多一次点击;空态显空 | 首屏偏长;搜索框"像输入框" | 筛选三处重复;层级感混乱 |

---

## 5. 推荐 + 为什么

**推荐 B(上下分区)。**

1. **最贴近用户原话的顺序**:「点进去两部分:①自由搜 ②按个性化需求找」—— B 的首屏就是"上面搜、下面按情况找",顺序和用户说话顺序一致,不用先做选择。
2. **少一次点击**:用户真正的痛点是"找材料麻烦";搜索框在第一屏第一个可点位置,点一下就是独立搜索页(满足"跳转独立界面",又不在壳页做就地输入,不产生两套输入状态)。
3. **"读取学习助理统计"变成看得见的东西**:4 行真实字段 + `实时读取` 徽标 + `为什么推这些` + 「看数据依据」展开五维 —— 这正好回应"别让人开盲盒",而 A 的卡内只能放 3 个 chip。
4. **结果页零新增视觉语言**:B 的两个结果页直接就是"频道页结果列表 + 条件条",与升级后的材料中心天然一致;A 同理但入口多一层,C 则要再造"密排 + 底栏 + 半屏筛选"一套。
5. **不制造第二个筛选入口**:A/B 的筛选只在搜索页出现(与频道页 chips 各管一段),C 的入口筛选台会和结果页/频道页三处重复 —— 将来改口径必漂。

**什么情况下改选 A / C**:
- 用户觉得"高级感、仪式感"优先于效率 → 选 **A**(两张 274px 大卡确实更抓眼,见 `find-material-A-entry.png`)。
- 用户是重度筛选党、希望"一屏看完全部条件再开工" → 选 **C**,但要接受 3~4 人日 + 后续三处筛选同步维护。

---

## 6. 真实渲染图(交付物)

出图方式与 `test/material_channel_render_test.dart` 一致:加载 `C:\Windows\Fonts\NotoSansSC-VF.ttf` + `MaterialIcons-Regular.otf`,
`RenderRepaintBoundary.toImage(pixelRatio: 3)`,手机逻辑尺寸 390×844 → 1170×2532。

| 文件 | 内容 |
|---|---|
| `build/ui_real/find-material-A-entry.png` + `docs/ui-preview/real/find-material-A-entry.png` | A 首屏(并列大卡) |
| `…/find-material-A-result.png` | A 自由搜结果页(分组 + 页码控件) |
| `…/find-material-B-entry.png` | B 首屏(搜索框 + 学习助理数据面板) |
| `…/find-material-B-result.png` | B 按需找结果页(依据卡 + 每卡"为什么推") |
| `…/find-material-C-entry.png` | C 首屏(模式切换 + 数据条 + 筛选台) |
| `…/find-material-C-result.png` | C 结果页(编号密排 + 底部固定页/动作条) |

复现:

```bash
cd /d/readflow && flutter test test/find_material_preview_test.dart --no-pub
```

**关于封面**:widget 测试没有网络,所以 6 张图里结果卡**一律走"无封面文字版式"** —— 这正是用户本轮定的规则
(「有真实封面才显示封面,没有就标题+翻译文字版式」)。有封面的分支(`coverHasImage` 为真 → 真图)不经测试图,
需要真机验一次。**不要**为了"图好看"在预览里塞渐变假封面,那和用户要求相反。

**渲染坑(已修,勿复现)**:预览屏如果没有 `Scaffold` / `Material` 祖先,`MaterialApp` 会把
`WidgetsApp.textStyle` 设成 Flutter 内部的 `_errorTextStyle`(`D:\flutter\packages\flutter\lib\src\material\app.dart:45-54`:
红字 + `decorationColor: 0xFFFFFF00` 的黄色双下划线),官方文档原话是 "Text widgets that lack a Material ancestor
will be rendered with an ugly red/yellow text style"(`:186-196`)。后果是**每一行文字底下都会多一条纯黄 (255,255,0) 下划线**。
本轮 `test/find_material_preview_test.dart` 的 `_shoot()` 已用
`DefaultTextStyle(style: TextStyle(decoration: TextDecoration.none))` 兜底,`_t()` 里也显式写了
`decoration: TextDecoration.none`(双保险,不改字号/行高所以版面不变)。以后写独立预览屏同样要兜这一层。

---

## 7. 现有能力可直接复用 vs 需要新增接口

### 7.1 可直接复用(不用改 services)

| 能力 | 位置(file:line) | 用在哪 |
|---|---|---|
| 需求事实源 + 全局排序 + AI 提示 | `lib/services/material_need.dart:34-48`、`:71-76`、`:79-86` | 按需找的查询词 / 排序 / AI hint |
| 学习助理数据组装(含降级) | `lib/services/tutor_snapshot.dart:73-104`;值对象 `:25-64` | 依据面板、五维依据展开 |
| 五维现状文案(带数字依据) | `lib/services/tutor_insights.dart:299`、`:197-244` | "看数据依据" |
| 快照/行为明细读取 | `lib/services/learner_snapshot_loader.dart:49-121` | 弱项、阅读速度、读完数 |
| 难度档与建议 | `lib/services/material_prefs.dart:48-111`;`lib/services/input_prefs.dart:412-436` | 难度 chip、调档提示 |
| 学习者模型读写 | `lib/services/learner_model_store.dart:22-32`、`:120-185` | 目标/兴趣/屏蔽项 |
| 已知词/难度判定 | `lib/services/learner_context.dart:27-33`、`:65-90`、`:93-98`、`:102-107` | 覆盖率与"难度适配"标注 |
| 公开源检索(含进度事件) | `lib/services/original_search.dart:60-100`、`:156-277` | 自由搜执行 + 搜索过程时间线 |
| 来源清单/可达性/取图顺序 | `lib/services/material_source.dart:265-351`、`:371-383`、`:516-528` | 来源筛选、封面 |
| 结果快照(按频道 id 存取) | `lib/services/material_channel.dart:232-310`、`:324-347` | 两个结果页"上次结果" |
| 真分页纯函数 | `lib/screens/input/material_channel_screen.dart:118-152` | 两个结果页分页 |
| 类型分组常量 | `material_channel_screen.dart` `_groupOrder`(`:2707`)/ `_groupLabels`(`:2718`)/ `_groupHeader`(`:2229`),行号随 task-3 变动 | 结果分组 |
| 封面文字版式 | `lib/widgets/shelf_cover_grid.dart:29`、`:40-60` | 无封面卡 |
| 保存到我的 / 补抓入库 | `material_channel_screen.dart` `_ingestToLibrary`(`:1061`)/ `_saveToMine`(`:1116`);行号随 task-3 变动 | 结果卡动作 |
| 搜索历史 | `lib/services/material_prefs.dart:393-406`、`:408-426` | "上次搜过" |
| 频道 id 形态(可扩展) | `material_channel.dart:19-46` + UI 侧 `_channel`(频道页现在的拼法) | 自由搜可用 `free:<归一化关键词>` 当 id,**不需要改 store** |

### 7.2 需要新增(建议的最小接口)

| 新接口 | 建议位置 | 内容 |
|---|---|---|
| `FindNeedContext` | `lib/services/find_need_context.dart`(新) | `static Future<FindNeedContext> load()`:拼 `MaterialNeed.load()` + `InputPreferences.load()` + `TutorSnapshotService.load()`;暴露 `bandLabel/goals/weakTags/readStats/blocked/reasons`;**只读**,不写偏好 |
| `FindNeedContext.reasons` | 同上 | 按 §3.2 级别 1 生成 3~4 条"为什么推这些",只用真实字段,空数据返回"待测"文案 |
| `MaterialNeedFilter.accepts(...)` | `lib/services/material_need.dart`(扩展纯函数) | 让**自由搜/按需找/频道页**都遵守 `blockedTopics`/`blockedKeywords`(现在注释说"一律遵守"`learner_preferences_screen.dart:26`/`:441`,但检索链路没有统一过滤点) |
| `MaterialResultList` 公共组件 | `lib/widgets/material_result_list.dart`(新) | 把 `_buildResultWidgets`/`_groupHeader`/`_resultCard`/页码控件从频道页抽出,task-3 与两个新页共用;**否则三份复制必漂** |
| `FreeSearchScreen` | `lib/screens/input/free_search_screen.dart`(新) | 输入 + 来源/类型/场景筛选 + `OriginalSearch` 执行 + `MaterialResultList` + `free:<关键词>` 快照 |
| `NeedSearchScreen` | `lib/screens/input/need_search_screen.dart`(新) | 依据卡 + `MaterialDiscovery().discover(...)`(复用频道页流程)+ `MaterialResultList` + `need:all` 快照 |
| `FindMaterialScreen`(壳) | `lib/screens/input/find_material_screen.dart`(新) | 选定方向的入口页(A/B/C 三选一) |
| 入口接线 | `material_hub_home_view.dart:624-679`、`material_center_screen.dart:317` | 卡片文案「找材料」+ 摘要改"两条路";`onOpenNeed` 改为 push 新壳页;`material_center_screen.dart` 顶部 `tune_rounded` 动作按钮(`:392`)也改指向 |
| 文案替换 | `material_taxonomy.dart:62-68` | `need` 方向 label 改「找材料」/subtitle 说明两入口(频道页 `_shortTitle` 会跟着变) |

**不需要新增**:数据库表、dbVersion、pubspec 依赖、新权限 —— 全部复用现有 Hive key(`learner_model_v2`、`keyMaterialPrefs`、`material_channel_*`)与 SQLite 表。

---

## 8. 如果选 B,实现顺序建议(给 Lead 排期)

1. **抽公共件**(0.5 日,阻塞项):`MaterialResultList` —— 与 task-3 的频道页改造合并做,避免两套结果列表。
2. `FindNeedContext` + 单测(0.5 日):输入用假 `InsightSource`,断言"没数据不出数字"。
3. `FreeSearchScreen`(0.5 日):先做"关键词 + 来源"两筛,结果 = `OriginalSearch` 直出 + 公共结果件。
4. `NeedSearchScreen`(0.5 日):拼 `FindNeedContext` + 复用频道页 discover 流程。
5. 入口壳页 + 接线 + 文案(0.3 日):截图回归(复用本文件 6 张图作为视觉基线)。
6. 真机验收重点:①有封面/无封面两种卡;②分页切页回顶;③保存到我的后"我的"里可见;④学习助理数据为空时的降级文案。

---

## 9. 附:本轮未做 / 需要 Lead 决定的事

- **频道页行号会漂**:本文 `material_channel_screen.dart` 的行号基于 task-3 改造中间态(当前 2361 行)。task-3 收尾后请按新行号复核 §1.4/§3.4 的引用。
- **`material_discover_screen.dart` 是否下线**:两条 AI 检索链路并存会让"找材料"又长出第二个入口。建议在实现「按需找」时把它降级为纯"AI 补长尾"弹层或被删除(需用户确认)。
- **搜索计费口径**:自由搜走公开源免费;按需找走 `MaterialDiscovery`(官方搜索按成功请求计费)。两个页面的成本提示要沿用频道页的"官方搜索约 ¥X(模型未计)"口径(`material_channel_screen.dart` `_resultMetaRow`),不能混在一起说。
- **语言筛选**:当前只有英文源。若要做"中英对照",属于新增数据源工程(不在本轮)。
