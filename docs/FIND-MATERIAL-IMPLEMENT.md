# 「找材料」A 方案 · 实施对照表（2026-11-06）

> 用户选型：**找材料走 A 方案（并列大卡：自由搜 / 按我的情况找）**。
> 设计稿：`docs/FIND-MATERIAL-REDESIGN-2026-11-06.md` §2 方向 A + §3 共用规格。
> 本文是**实现对照表**：设计每一条 → 代码 file:line → 渲染图/测试，用来给 QA 逐条打勾。
> 约束遵守：不 commit / 不改 pubspec / 不加依赖 / 不改 dbVersion / 不改 DB 结构。

---

## 0. 交付清单（一眼核对）

| 交付 | 位置 | 状态 |
|---|---|---|
| 入口页「找材料」(A 并列大卡) | `lib/screens/input/find_material_screen.dart` | ✅ |
| 自由搜独立页 | `lib/screens/input/free_search_screen.dart` | ✅ |
| 按我的情况找独立页 | `lib/screens/input/need_search_screen.dart` | ✅ |
| 共用结果列表件(分组/分页/卡片/动作) | `lib/widgets/material_result_list.dart` | ✅ |
| 依据数据层(读学习助理) | `lib/services/find_need_context.dart` | ✅ |
| 频道页**薄委托**：渲染层（`MaterialResultPageBar`/`MaterialResultGroupHeader`/`MaterialResultCard`/`MaterialResultCoverThumb`）共用公共件，检索/快照/保存行为保留在频道页 | `lib/screens/input/material_channel_screen.dart` | ✅ |
| 入口接线(材料中心,3 处) | `material_center_screen.dart` | ✅ |
| 首页卡片文案「找材料」 | `material_hub/material_hub_home_view.dart` | ✅ |
| taxonomy need 方向改名 | `services/material_taxonomy.dart` | ✅ |
| D6 [历史] sheet | `find_material_screen.dart` `_openHistory` / `_HistorySheet` | ✅ |
| P2-8 频道页「去设置需求」→ settingsOnly | `material_channel_screen.dart` `_openNeedSettings` | ✅ |
| 单测 | `test/find_need_context_test.dart`、`test/material_result_list_test.dart` | ✅ |
| 逐屏渲染 11 张 | `docs/ui-preview/real/find-material-impl-*.png` | ✅ 见 §8 |
| 频道页回归 | `test/material_channel_paging_test.dart` + `test/material_channel_render_test.dart` | ✅ |

---

## 1. 入口页（设计 §2 方向 A · 首屏结构）

设计线框：`34px 标题` + `两张等宽大卡` + `最近搜过 chips` + `上次结果卡` + 右上角 `[历史]`。

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 34px 标题「找材料」+ 副标题「两条路:自己搜,或者让软件按你的情况找。」 | `find_material_screen.dart:171-190` | `find-material-impl-entry.png` |
| 两张**等宽**大卡，同一高度 274 | `find_material_screen.dart:191-212`（`SizedBox(height: 274)` + `Row` + 两个 `Expanded`） | 同上 |
| 自由搜卡：图标 + 标题 + 说明 + 能筛什么 chips + 「上次搜过」+ CTA | `_freeCard` `find_material_screen.dart:307-323`（真实值来自 `_lastFreeKeyword()` `:642`，数据源 `FindSearchHistory.load()`） | 同上 |
| 按情况找卡：图标 + 标题 + 说明 + 难度档/目标/弱项 chips + 「基线 已掌握 N 词」+ CTA | `_needCard` `find_material_screen.dart:325-347`（`ctx.need.band` / `ctx.goals` / `ctx.weakTags` / `ctx.vocabEstimate`；没测过写「待测(去测一次词汇量)」） | 同上 |
| 卡点击 → 各自**独立页** | `_openFreeSearch` `:104-112` → `FreeSearchScreen`；`_openNeedSearch` `:114-121` → `NeedSearchScreen` | — |
| 最近搜过 chips（点一条回填搜索） | `_recentHeader` `:487-508`、`_recentChips` `:510-555`（最多 4 条；点击 push `FreeSearchScreen(initialQuery: query)`） | 同上 |
| 上次结果卡（快照真实数据：篇数 + 时间） | `_lastRunStrip` `:557-610`；数据来自 `MaterialChannelStore.loadSnapshot('need:all')`（`_load` `:69-102`） | 同上 |
| **D6 [历史]**：右上角胶囊 → sheet 列全部历史、点一条回填搜索、可清空 | 按钮 `:217-254`；`_openHistory` `:123-145`；sheet 组件 `_HistorySheet` `:671-790`；数据/清空 `FindSearchHistory`（`find_need_context.dart:335-380`） | `find-material-impl-history.png` |
| 空态：还没搜过时的提示 | `_recentChips` 内 `:511-517`（"还没有搜索记录 —— 点「自由搜」开始第一次。"） | — |

> 注：入口页的 `initialContext/initialHistory/initialLastRun` 是**仅渲染测试用**的注入参数（生产永不传），保证截图不依赖 Hive/DB。

---

## 2. 自由搜（设计 §2 A · 输入与筛选 / §3.3 筛选规格）

| 设计条目 | 实现 | 渲染图/测试 |
|---|---|---|
| 单行搜索框，回车即搜 | `_searchBar` `free_search_screen.dart:350-430`；`_runSearch` `:130-247` | `find-material-impl-free-empty.png` |
| 空关键词 → 推荐检索词（不弹空白页） | `_runSearch` `:133-138` + `_recommendedQuery` `:249-259`（场景预设 → `OriginalSearch.defaultQueryFor(category)` → `english reading` 兜底） | — |
| **来源**筛选：9 个真实公开源，实测可用标标记 | `_sourceRow` `:432-456`；数据 `MaterialSourceService.sources` / `measuredReachable`；请求时以 `sourceIds` 收窄（`OriginalSearch.search(...sourceIds:)` `:154-159`）。**筛选区用 `Wrap` 换行**（`_chipRow`），390 宽下每个 chip 完整可见，不横向裁切 | `find-material-impl-free-empty.png` |
| **类型**筛选：书籍/论文/外刊新闻/播客/百科 **5 类**（与 `MaterialSource.kind` 对齐） | `_typeRow` `free_search_screen.dart:458-520`（6 个 chip：不限 + 5 类）+ `_categoryOf:272-282` + `_selectedSourceIds`（类型→真实来源收窄） | 同上 |
| 类型 → 来源的真实映射（**不是造数据**） | 书籍→`gutenberg`；论文→`arxiv`；外刊新闻→`npr`(+`nasa`/`sciencedaily` 同类)；播客→`bbc_le`/`voa_le`/`ted`；百科→`wikipedia` | 映射表见下方 §2.1 |
| 百科的诚实降级 | `_wikiFreshItems` `free_search_screen.dart:395-440`：`MaterialSourceService.listItems('wikipedia', limit: 10)` 拉真实随机条目 → 本地关键词筛 → 命中几条报几条；结果页 `_notes` 明说"维基没有关键词检索接口" | `find-material-impl-free-empty.png`（类型行可见「百科」） |
| **难度**筛选：来源级预计区间，文案写明"非精确覆盖率"；未抓正文**不标真实难度** | `_difficultyRow` `:490-516`；过滤 `_bandMatches` `:279`；每张卡 `estimateLabel` 来自 `MaterialLibrary.estimateDifficulty(sourceId:, kind:)`（`:171-180`） | `find-material-impl-free-result.png`（卡片上"预计 B1~B2 · 中等"） |
| **场景**：`MaterialTaxonomy.scene` 的真实检索词预设（点了填入搜索框，不做假过滤器） | `_sceneRow` `:518-560` | 同上 |
| 执行：`OriginalSearch.search` + 逐源进度事件 | `:160-164`；进度回调 `_onProgress` `:300-303` | — |
| 搜索过程折叠卡（跑完自动收起） | `_processCard` `:665-739`；`SearchTimeline` 复用 | `find-material-impl-free-result.png`（收起态） |
| 空结果 → 源说明 + 再搜一次 | `_emptyAfterRun` `:802-836` | `find-material-impl-free-empty-result.png` |
| 黑名单（屏蔽题材/关键词）真的过滤候选 | `_runSearch` `:181-188` 调 `InputPreferences.allowsMaterial`（唯一口径，与材料推荐一致） | 单测 `find_need_context_test.dart` |
| 搜索历史落盘（与 MaterialPrefs 同一 key） | `FindSearchHistory.remember(query)`（`find_need_context.dart:369-370`）在搜索成功后调用 `:229` | — |

### 2.1 自由搜「类型」5 类 → 真实来源映射（QA W1 的书面依据）

| 类型 chip | `MaterialSource.kind` | 本次检索用的分类(category) | 收窄到的真实来源(`MaterialSourceService.sources`) | 可检索性 |
|---|---|---|---|---|
| 书籍 | `book` | 书籍 | `gutenberg` | ✅ Gutenberg 站内检索 |
| 论文 | `paper` | 论文 | `arxiv` | ✅ arXiv 官方 API |
| 外刊新闻 | `news` | 外刊 | `npr`、`nasa`、`sciencedaily` | ✅ RSS 列表 + 标题关键词过滤 |
| 播客 | `podcast` | 外刊 | `bbc_le`、`voa_le`、`ted` | ✅ RSS 列表 + 标题关键词过滤(音频源) |
| 百科 | `wiki` | —（不走 OriginalSearch） | `wikipedia` | ⚠️ 维基源**没有关键词检索接口**：只能拉"随机条目池"再本地筛，见 `_wikiFreshItems`；页面上会如实写明 |

> 说明：`bbc_le/voa_le/ted/wikipedia` 在大陆网络实测超时（`material_source.dart:371-383`），
> 界面对「实测可用」的 5 个源有徽标；选到不可达源时 `OriginalSearch` 会按源报错并给出
> `notes`（不静默）。这两点都是既有服务行为，自由搜没有覆盖或篡改。

---

## 3. 按我的情况找（设计 §2 A · 个性化面板 / §3.1 真实字段 / §3.2 两级文案）

| 设计条目 | 实现 | 渲染图/测试 |
|---|---|---|
| 四行依据：难度档 / 学习目标 / 弱项 / 最近阅读 | `_basisCard` `need_search_screen.dart:489-566` + `_basisRow` `:568-640`；数据 `FindNeedContext.rows`（`find_need_context.dart:164-215`） | `find-material-impl-need-panel.png` |
| 难度档 ← `MaterialNeed.band`（`MaterialPrefs.band`） | `find_need_context.dart:170-177` | 同上 |
| 学习目标 ← `InputPreferences.examGoals`(← `LearnerModel.goals`) | `:179-186` | 同上 |
| 弱项 ← `TutorDashboard.source.errorTagCounts`（`learner_snapshot_loader` 错误标签） | `:188-199`；`weakTags` `:123-133`（次数降序、最多 3 个） | 同上（"语法:时态 8 次 · 冠词 5 次"） |
| 最近阅读 ← `materialsFinished30d` + 实测 `readingWpm` | `:201-214`、`readingWpm` `:135-146` | 同上（"近 30 天读完 4 篇 · 180 词/分"） |
| **缺数据 = 「待测 + 怎么测」，不显示数字** | `:171`（`待测 · 还没设置学习目标`）、`:192`（`待测 · 做一次写译批改或测验就能算`）、`:207`（`待测 · 先读完一篇…`）+ 每行 `hint` 文案；整块无数据还提示"助理还没数据" | `find-material-impl-need-empty.png`；单测（未测行正则无数字） |
| 「为什么推这些」= 级别 1（只用画像 + 需求字段） | `FindNeedContext.reasons`（`find_need_context.dart:217-249`）；UI `_basisCard` `:536-563` | `find-material-impl-need-panel.png` |
| 「为什么推这篇」= 级别 2，**必须补抓正文算完覆盖率才允许出现** | `_reasonFor` `need_search_screen.dart:292-307`：`item.analysis?.knownTokenRatio == null` 直接返回 null → 卡片不显示依据行 | `find-material-impl-need-result.png`（有 coverage → 出现"为什么推:难度 96% …"） |
| 「看数据依据」弹层（把背后字段摊开） | `_showBasisSheet` `:778-900`（词汇量基线/CEFR/目标/兴趣/语速/读完数/在读/每日分钟/错误标签/屏蔽项；`!hasTutorData` 时提示去测一次） | — |
| 「改需求」→ 需求设置页（只读入口不重复造编辑器） | `_openNeedSettings` `:271-290` → `MaterialBrowseScreen(direction: need, settingsOnly: true)`（Lead 提供的参数） | — |
| 检索走真实流水线（AI 计划 → 公开源+官方搜索 → 抓正文 → 本地算难度） | `_runSearch` `:134-269` 调 `MaterialDiscovery().discover(...)`（与频道页同一入口）；`planNextQueries` 用于「继续找更多」 | — |
| 成本如实标注（官方搜索按成功请求计费，模型未计） | `_metaRow` `:694-714`（`官方搜索约 X 元(模型未计)`） | `find-material-impl-need-result.png` |
| 空态 / 跑过但 0 条 | `_introCard` `:716-747`、`_emptyAfterRun` `:749-776` | — |

---

## 4. 两份结果页共用 `MaterialResultList`（设计 §2 A + §3.4 结果页布局契约）

| 设计要素 | 公共件实现 | 频道页复用位置 | 新页复用位置 |
|---|---|---|---|
| **类型分组**（教材/应试真题/书籍/论文/外刊新闻/文章/其他，组序固定） | `material_result_list.dart`：`materialResultGroupOrder:76`、`materialResultGroupLabels:88`、`groupMaterialResultItems<T>:208-266` | `material_channel_screen.dart:2235-2245`（`_groupedResults` 转调） | `MaterialResultList` `material_result_list.dart:896` 内部 |
| **组内排序**（有真实覆盖率的在前 → 权威度 → 原始顺序） | `groupMaterialResultItems` 的 `compare`:230-258 | 同上 | 同上 |
| **每页 10 条** | `materialResultPageSize:52`；`materialResultPageCount/Clamp/Range:55-…` | `material_channel_screen.dart:101-137`（`materialChannelPage*` 全部**转调**公共件，签名不变） | `MaterialResultList` + `MaterialResultController.pageCount` |
| **页码控件**（上一页 / 第 X / Y 页 / 下一页；首末页禁用） | `MaterialResultPageBar:782-894`（禁用=0.45 透明+不可点） | `material_channel_screen.dart:2218-2225`（`_pageBar` 转调） | `MaterialResultList:976-984` |
| **切页回顶** | 行为在父级：频道页 `_goPage` → `_scrollToTop()` | `material_channel_screen.dart` `_goPage`（约 `:560`） | `free_search_screen.dart:642-646`、`need_search_screen.dart:440-444` |
| **有真封面才显示封面** | `MaterialResultCard` 判 `shelfCoverHasImage`；真图用 `MaterialResultCoverThumb:451-511`（无图中性占位、不画渐变假封面）；无图则纯文字版式 | `:2252`（`_resultCard` 转调）；「我的」卡缩略图也换成同一件 | 两份结果页同一张卡 |
| **无封面文字版式** | 卡面：标题(2 行) + 来源/类型/难度胶囊 + 摘要(2 行) + 按钮行 | 同上 | `find-material-impl-no-cover.png`（组件版式对照图） |
| **开始读**（补抓正文 → 质量闸门 → 入库 → 阅读器） | `MaterialResultController.read` `material_result_list.dart:1170-1210` | 频道页保留自己的 `_startRead`（行为未动） | 两个新页共用 controller |
| **保存到我的**（入库 + 保存关系 + 去隐藏记录） | `MaterialResultController.save:1212-1262` | 频道页保留自己的 `_saveToMine` | 两个新页共用 |
| **打开原文 / PDF**（`looksLikePdfUrl` 决定按钮文案） | `MaterialResultController.openOriginal:1264-1270`；卡片按钮 `MaterialResultCard` | 频道页 `_openOriginal` | 两个新页共用 |
| **继续找更多**（追加 + 页数增加 + 跳到第一条新结果页） | `MaterialResultList.onContinue` + `MaterialResultController.applyRun(append: true)`:1090-1155 | 频道页 `_startDiscovery(more: true)`（行为未动） | `free_search_screen.dart:641-660`（放宽来源再搜）、`need_search_screen.dart:436-462`（AI 换检索词） |
| **抓不到正文的解释**（不假装可读） | `MaterialResultCard.unavailableHint` + `MaterialResultController._unavailableHint` | 频道页 `_resultCard` 传 `unavailableHint` | 两个新页同一件 |
| **快照身份** | `free:<归一关键词>`（`free_search_screen.dart:141`）、`need:all`（`need_search_screen.dart:60`），复用 `MaterialChannelStore`（不改表/不新增 key 结构） | 频道页 `topic:/form:/scene:/need:` 原样 | — |

---

## 5. 接线（材料中心 → 找材料）

| 位置 | 改动 | file:line |
|---|---|---|
| 材料中心首页「按需求找材料」卡（含空态胶囊） | 文案「找材料」+ 副标题「自由搜,或按你的学习情况找」 | `material_hub_home_view.dart:655`（卡片标题）、`:240`（空态胶囊）、`:662`（副标题） |
| 点击接线 | `onOpenNeed: _openFindMaterial`（原 `MaterialTaxonomy.need` 频道页） | `material_center_screen.dart:317` |
| 顶部 tune 按钮（两处：大头部 + 紧凑顶栏） | 同样指向 `_openFindMaterial` | `material_center_screen.dart:392`、`:495` |
| 新方法 | `_openFindMaterial()` push `FindMaterialScreen`，回来 `_load()` 刷新 | `material_center_screen.dart:242-252` |
| 旧 `MaterialBrowseScreen` 入口下线 | 材料中心不再直接进入需求编辑页；需求编辑只剩「按我的情况找 → 改需求」与频道页「去设置需求」两处，均 `settingsOnly: true` | `material_channel_screen.dart:1422-1438`（P2-8） |
| taxonomy 文案 | need 方向 label「找材料」/ subtitle「自由搜 · 或按你的学习情况找」/ icon | `material_taxonomy.dart:62-70` |

---

## 6. 频道页回归说明（行为零变化）

> QA W2 复核提示：频道页里 `_resultCard`/`_groupHeader`/`_pageBar` **仍然有名，
> 但都已经是"薄委托"**（file 里只剩转调公共件的那几行）：
> - `_resultCard(_ChannelItem)` at `material_channel_screen.dart:2257` → 只做 `param 映射`，
>   **:2261 `return MaterialResultCard(...)`**（没有第二套卡片实现）；
> - `_groupHeader(...)` at `:2234` → `:2235 MaterialResultGroupHeader(...)`；
> - `_pageBar(...)` at `:2220` → `:2227 MaterialResultPageBar(...)`；
> - `_groupedResults()` at `:2243` → `groupMaterialResultItems<_ChannelItem>(...)`；
> - `_pageGroupSlices(page)` at `:1968-1976` → `materialResultPageSlices<_ChannelItem>(...)`；
> - 本文件已删除本地 `_ResultGroup`/`_CoverThumb`/`_pageButton`/`_groupOrder`/`_groupLabels`/`_kindChipLabel`/`_fmtDay`/`dart:math`。
> 搜索/保存/打开原文/分页状态机仍是频道页自己的（**本轮不动行为**），只有"展示"换成公共件。

- **只抽展示**：`_resultCard` → `MaterialResultCard`；`_pageBar` → `MaterialResultPageBar`；`_groupHeader` → `MaterialResultGroupHeader`；`_groupedResults`/`_pageGroupSlices` → 泛型公共函数。
- **分页语义不变**：`materialChannelPageSize/Count/Clamp/Range` 改为转调公共件，**函数名/签名/返回值语义完全一致**（`material_channel_paging_test.dart` 直接 import 它们，未改测试）。
- **封面纪律不变**：仍只在 `imageUrl` 真有 http(s) 图时画缩略图；「我的」卡同规则。
- **渲染图不变**：`test/material_channel_render_test.dart` 仍出 5 张原文件名图（channel-discover-p1/p2/my 等），条数/分组/封面纪律不变。
- 回归结果见 §8。

---

## 7. 数据来源对照（每条都能核对，不编）

| 面板/文案 | 真实字段 | file:line |
|---|---|---|
| 难度档 i+10 | `MaterialNeed.band` ← `MaterialPrefs.band` | `material_need.dart:34-48`；`material_prefs.dart:48-111` |
| 学习目标 四六级 | `InputPreferences.examGoals` ← `LearnerModel.goals` | `input_prefs.dart:464`、`:537`；`learner_model.dart:113` |
| 兴趣题材 | `LearnerModel.interests` ∪ `MaterialPrefs.genres` | `input_prefs.dart:466-467`、`:538` |
| 弱项「时态 8 次」 | `TutorDashboard.source.errorTagCounts`（错误档案 + 写译批改聚合） | `tutor_snapshot.dart:118-132`、`:175-196`；`tutor_insights.dart:104-195` |
| 近 30 天读完 N 篇 | `InsightSource.materialsFinished30d` | `tutor_snapshot.dart:134-154`、`:184` |
| 阅读速度 N 词/分 | `InsightSource.readingWpm`（实测优先） | `tutor_snapshot.dart:183`；`learner_context.dart:93-98` |
| 词汇量基线 | `LearnerModel.vocabEstimate` + `LearnerContext.describeBaseline` | `learner_model.dart:93`；`learner_context.dart:41-59` |
| 屏蔽题材/关键词 | `LearnerModel.blockedTopics/blockedKeywords` → `InputPreferences` | `learner_model.dart:125-129`；`input_prefs.dart:481-485` |
| 搜索历史 | `MaterialPrefs` 同一个 Hive key（`FindSearchHistory` 读写） | `material_prefs.dart:393-426`；`find_need_context.dart:335-380` |
| 预计难度标签 | `MaterialLibrary.estimateDifficulty`（来源/类型估算，非精确覆盖率） | `material_library.dart:692-747` |

**诚实边界（实现里已守住）**
- 无数据行：`FindNeedRow.measured == false`，值文案以「待测」开头且**不含数字**（单测正则校验）。
- 级别 2「为什么推」只在 `analysis.knownTokenRatio != null` 时出现。
- 自由搜的难度是**来源级预计区间**，文案写"按来源预估,非精确覆盖率"；抓正文入库后阅读器才给真实认知率。
- 场景是**检索词预设**（公开源没有场景元数据），不伪装成过滤条件。

---

## 8. 测试与验收

> 说明：本轮实施期间另一个 agent 正在改 `lib/screens/input/material_reader_screen.dart`，
> 中间态编译错误（`ReaderActionBar/ReaderMoreAction` undefined）会让所有 import 到
> 阅读器的测试**在 loading 阶段失败**（我的两份结果页要用 `MaterialReaderScreen` 做
> 「开始读」，频道页回归同理）。下表状态以阅读器恢复后重跑为准，恢复前不虚报"全绿"。

| 项 | 命令 | 状态 |
|---|---|---|
| 依据数据单测 | `bash tool/lockrun.sh test test/find_need_context_test.dart --no-pub` | ✅ **+8 全过**（2026-11-06 23:36 实测） |
| 公共件单测(分页/分组/卡片/页码/控制器) | `bash tool/lockrun.sh test test/material_result_list_test.dart --no-pub` | ✅ 14 通过 |
| 频道页分页回归 | `bash tool/lockrun.sh test test/material_channel_paging_test.dart --no-pub` | ✅ 通过 |
| 频道页渲染回归(5 张图，文件名/视觉不变) | `bash tool/lockrun.sh test test/material_channel_render_test.dart --no-pub` | ✅ 通过，5 张图已重出 |
| 逐屏渲染(11 张) | `bash tool/lockrun.sh test test/find_material_render_test.dart --no-pub` | ✅ 11 张已生成 + 逐张 read_image 自检（字体/图标真实、无黄线、无裁切）+ `takeException()` 断言无布局异常 |
| 材料中心首页回归(文案变更) | `test/material_hub_test.dart`（Lead 批准把 `'按需求找材料'` 断言改 `'找材料'`，只改这一行） | ✅ 通过 |

> 6 个测试文件同一批跑：**52 passed / 全绿**（含 find_need_context 8、material_result_list 14、频道页分页/渲染、入口渲染 11、hub 回归）。

**analyze 证据（目录级，避免拖慢全局队列）**

| 范围 | 结果 |
|---|---|
| `bash tool/lockrun.sh analyze --no-pub lib/widgets` | **No issues found!** |
| `bash tool/lockrun.sh analyze --no-pub lib/services/find_need_context.dart` | **No issues found!** |
| `bash tool/lockrun.sh analyze --no-pub lib/screens/input` | 8 issues，**全部 info、0 error / 0 warning**（我的 2 条是风格 info：`use_null_aware_elements` @find_material_screen:339、`unnecessary_underscores`:745；其余 6 条是既有 `process_chat.dart`/`ai_article_section.dart` 的存量 info） |

**Lead 复核意见（筛选区右侧被裁）已修**：`free_search_screen.dart` 的 `_chipRow` 由
「固定高 34 的横向 `ListView`」改为 **`Wrap` 换行**，390 宽下 9 个来源 chip（含"实测可用"徽标）/
6 个类型 chip / 4 档难度 + "按来源预估,非精确覆盖率"说明 / 4 个场景 chip **全部完整可见**；
渲染测试新增 `expect(tester.takeException(), isNull)` 断言，11 张图均无布局异常（不裁切、不 overflow），
`find-material-impl-free-result.png` 已按新筛选区重出。

**逐屏渲染图（390×844 @3x，真字体+真图标；`build/ui_real/` 与 `docs/ui-preview/real/` 双写）**

| # | 文件 | 内容 |
|---|---|---|
| 1 | `find-material-impl-entry.png` | 入口页：34px 标题 + 两张等宽大卡 + 最近搜过 + 上次结果 |
| 2 | `find-material-impl-free-empty.png` | 自由搜空态：搜索框 + 来源/类型/难度/场景筛选 + 使用说明 |
| 3 | `find-material-impl-free-result.png` | 自由搜结果：分组（外刊/书籍/教材/真题）+ 封面规则 + 页码控件 |
| 4 | `find-material-impl-free-empty-result.png` | 自由搜空结果：源说明 + 再搜一次 |
| 5 | `find-material-impl-need-panel.png` | 按情况找：4 行真实依据 + 为什么推这些 + 主按钮 |
| 6 | `find-material-impl-need-result.png` | 按情况找结果：每卡"为什么推" + 分组 + 页码 |
| 7 | `find-material-impl-free-pager.png` | 自由搜结果**滚到底**：页码控件（上一页/第X页/下一页）+ 继续找更多 |
| 8 | `find-material-impl-need-pager.png` | 按情况找结果**滚到底**：页码控件 + 继续找更多 |
| 9 | `find-material-impl-need-empty.png` | 按情况找缺数据降级（全部「待测」、无数字） |
| 10 | `find-material-impl-no-cover.png` | 卡片版式对照：无真封面 → 纯文字（不画假封面） |
| 11 | `find-material-impl-history.png` | D6 搜索历史 sheet（点一条回填 / 可清空） |

> 说明：渲染用假数据喂**生产组件**（`FindMaterialScreen(initialContext: …)` 等只测试可用的注入参数），不联网、不读写 Hive；布局/组件/文案与真机一致。

---

## 9. 已知边界 / 下一轮可做

1. 自由搜的「继续找更多」= 放宽来源再搜一轮；公开源检索是确定性的，**没有新增时会提示"已经找全"**（不假装有更多）。
2. 预计难度不落快照（快照契约 9 键不放新字段），所以**重进页面后预计难度标签不再显示**；真实覆盖率在补抓正文后照常显示。这是"不改 store 契约"的代价，已写在此处备查。
3. `MaterialBrowseScreen` 仍存在（Lead 维护的 `settingsOnly` 模式），只用于设置需求；旧页的"结果列表/AI 补长尾"不再有入口。
4. 频道页「按需求」方向的 `_needSummaryBar` 仍保留（未接新页），因为频道页四个方向共用一套头部;本轮只保证入口不再从材料中心直连。

---

## 10. 交互联通性自检（读代码逐条确认，非"看起来接了"）

| 交互 | 实现链路 | 结论 |
|---|---|---|
| 入口 → 自由搜 | 卡片 `_freeCard` → `_openFreeSearch(initialQuery: 上次搜过)` → `FreeSearchScreen(initialQuery)`；返回后 `await push` 结束 → `_load()` 重读历史/上次结果 | ✅ 接通 |
| 入口 → 按情况找 | 卡片 `_needCard` → `_openNeedSearch` → `NeedSearchScreen`；返回后 `_load()` | ✅ 接通 |
| 返回路径 | 两个子页 `Navigator.maybePop`（顶部圆形返回）；系统返回同效；入口页 `Navigator.maybePop` 回材料中心 | ✅ 接通 |
| 上次结果卡 → 结果页 | `_lastRunStrip` onTap = `_openNeedSearch`（`need:all` 快照在下页 `_loadAll → controller.loadSnapshot` 恢复） | ✅ 接通 |
| 快照恢复（按需找） | `NeedSearchScreen._loadAll` → `MaterialChannelStore.loadSnapshot('need:all')` → 复用 `MaterialResultItem.fromSnapshot` → `_searchedThisSession=true` | ✅ 接通 |
| 快照恢复(自由搜) | 带关键词进入 → `_restoreSnapshot(query)` → `loadSnapshot('free:<归一关键词>')` → 有结果直接显示"上次结果" | ✅ 接通 |
| 搜索历史（D6）点一条回填 | sheet `Navigator.pop(query)` → `_openHistory` 收到后 push `FreeSearchScreen(initialQuery: query)` | ✅ 接通 |
| 清空历史 | sheet「清空」→ `FindSearchHistory.clear()`（写回 `{}` 到同一 Hive key）→ sheet 本地清空 + 入口页 `setState(_history=[])`；入口"上次搜过"立刻变"还没搜过" | ✅ 接通 |
| 改需求（按需找页内） | `_openNeedSettings` → `MaterialBrowseScreen(settingsOnly: true)` → 返回后重读 `InputPreferences` + `_loadAll()`（依据面板跟着变） | ✅ 接通 |
| 开始读 / 保存到我的 / 打开原文 | 卡片 → `MaterialResultController.read/save/openOriginal` → 补抓正文（质量闸门）→ `MaterialLibrary.ingestText` 入库 → `MaterialChannelStore.addSavedMaterial(storeId, id)` → `MaterialReaderScreen` / `launchExternalUrl` | ✅ 接通（与频道页同一套行为） |
| 切页回顶 | `MaterialResultList.onPageChanged` → 父页 `controller.goPage + _scrollToTop()`（jumpTo(0)） | ✅ 接通 |
| B7-③ 频道页撤隐藏失败 | `_saveToMine` 里 `removeHiddenMaterial` 返回 false 现在 `debugPrint` 记录（不阻塞保存、不扩大改动） | ✅ 已修 |

---

## 11. 我改动的文件清单（给 Lead 全量 analyze 归因用）

| 文件 | 类型 | 改动范围 |
|---|---|---|
| `lib/screens/input/find_material_screen.dart` | 新增 | 全文（~790 行） |
| `lib/screens/input/free_search_screen.dart` | 新增 | 全文（~880 行） |
| `lib/screens/input/need_search_screen.dart` | 新增 | 全文（~900 行） |
| `lib/widgets/material_result_list.dart` | 新增 | 全文（~1330 行） |
| `lib/services/find_need_context.dart` | 新增 | 全文（~380 行） |
| `lib/screens/input/material_channel_screen.dart` | 修改 | 仅"结果件抽取 + P2-8 + B7-③"：import `material_result_list`（`:25`）、`inferChannelKind` 转调（`:92-97`）、`materialChannelPageSize/Count/Clamp/Range` 转调（`:101-137`）、`_saveToMine` 撤隐藏失败日志（`:1158-1174`，判断点在 `:1163`）、`_openNeedSettings`（`:1431-1447`）、`_pageGroupSlices` 转调（`:1963-1976`）、`_pageBar`/`_groupHeader`/`_groupedResults`/`_resultCard` 转调（`:2220-2290`）；删除本地 `_ResultGroup`/`_CoverThumb`/`_pageButton`/`_groupOrder`/`_groupLabels`/`_kindChipLabel`/`_fmtDay`/`math` import |
| `lib/screens/input/material_center_screen.dart` | 修改 | 仅接线：import `find_material_screen`（`:19` 附近）、`onOpenNeed: _openFindMaterial`（`:318`）、tune 按钮两处（`:393`、`:496`）、新增 `_openFindMaterial()`（`:242-252`） |
| `lib/screens/input/material_hub/material_hub_home_view.dart` | 修改 | 仅文案两处：卡片标题「找材料」（`:655` 附近）、空态胶囊（`:240` 附近）、副标题（`:662` 附近） |
| `lib/services/material_taxonomy.dart` | 修改 | need 方向 label/subtitle/icon（`:62-70`） |
| `test/material_hub_test.dart` | 修改 | 仅 `:232` 断言 `'按需求找材料'` → `'找材料'`（Lead 批准） |
| `test/find_need_context_test.dart` | 新增 | 全文 |
| `test/material_result_list_test.dart` | 新增 | 全文 |
| `test/find_material_render_test.dart` | 新增 | 全文（11 张逐屏渲染） |
| `docs/FIND-MATERIAL-IMPLEMENT.md` | 新增 | 本文 |

**没有动**：`material_reader_screen.dart`、`material_browse_screen.dart`（Lead 维护）、`pubspec.yaml`、`dbVersion`、DB 结构、其它屏幕。

---

## 12. QA 两条纠偏的处理结论

### W1（类型筛选 5 类）→ 已按选项 ① 补齐
- 自由搜「类型」现在 6 个 chip（不限 + 书籍/论文/外刊新闻/播客/百科），见 `free_search_screen.dart` `_typeRow`；
- 5 类都有**真实来源映射**（§2.1 表）：书籍→gutenberg、论文→arxiv、外刊新闻→npr(+nasa/sciencedaily)、播客→bbc_le/voa_le/ted、百科→wikipedia；
- 百科类**如实降级**：维基源没有关键词检索接口，只能拉 `listItems('wikipedia')` 的随机条目池再本地按关键词筛（`_wikiFreshItems`），结果页 `notes` 会写明"从随机条目池筛出 N 条"；这不是静默少做，是把能力边界摆在界面上。

### W2（频道页是否真的改用公共件）→ 已是选项 ①：**频道页薄委托**
> 准确表述（QA 验收口径）：频道页**渲染层**（`MaterialResultPageBar` / `MaterialResultGroupHeader` /
> `MaterialResultCard` / `MaterialResultCoverThumb`）共用 `lib/widgets/material_result_list.dart`；
> **检索 / 快照 / 保存 / 打开原文等行为仍保留在频道页**（本轮不动行为）。
逐条证据（`lib/screens/input/material_channel_screen.dart`）：
- `_resultCard(_ChannelItem)` at `:2257` → **`:2261 return MaterialResultCard(...)`**（没有第二套卡片实现，参数逐个映射）；
- `_groupHeader(...)` at `:2234` → `:2235 return MaterialResultGroupHeader(...)`；
- `_pageBar(...)` at `:2220` → `:2227 return MaterialResultPageBar(...)`；
- `_groupedResults()` at `:2243` → `groupMaterialResultItems<_ChannelItem>(...)`（`:2244`）；
- `_pageGroupSlices(page)` at `:1963` → `materialResultPageSlices<_ChannelItem>(...)`（`:1971`）；
- `_openNeedSettings()` at `:1431-1447`（P2-8：push `settingsOnly: true` + `push<bool>` 接结果）；
- `_saveToMine` 撤隐藏失败日志（`removeHiddenMaterial` @`:1163`，B7-③）；
- 本文件已**删除**本地 `_ResultGroup`/`_CoverThumb`/`_pageButton`/`_groupOrder`/`_groupLabels`/`_kindChipLabel`/`_fmtDay`/`dart:math`；
- 行为零变化回归：`material_channel_paging_test` + `material_channel_render_test`（5 张图）全绿。

---

## 13. 遗留（待用户确认，非本轮范围）

- **旧 AI 找材料页 `MaterialDiscoverScreen` 仍与 5 个入口并存**（`input_home.dart:161`、
  `legacy_material_center_screen.dart:1459`、`material_browse_screen.dart:270`、
  `material_category_screen.dart:210`、`category_material_screen.dart:833`）。
  现在材料中心的「找材料」已走新页（自由搜 / 按我的情况找），这条旧 AI 检索链路**是否下线/合并**
  需要用户拍板（它不在本轮「找材料」写作用域内，未擅自删除）。

---

## 14. 第三轮补强(2026-11-07 · 用户真机反馈第 4/5 条)

> 范围:只动「自由搜 / 结果卡」+ 新增 AI 改写服务。**不改**检索逻辑(归 W1a 的
> `material_discovery`/`content_quality`/`material_taxonomy`/频道页)、不改 DB 结构、
> 不加依赖(封面用的 `dio` 是已有直接依赖)。

### 14.1 反馈 → 根因 → 实现 → 渲染

| # | 用户反馈 | 根因(本轮核验) | 实现(file:line) | 渲染图 |
|---|---|---|---|---|
| 4-① | 自由搜顶部输入框文字上半截被裁 | 搜索框容器写死 `height: 42` + `TextField(isDense)` 的默认内边距,文字可用高度不足,InputDecorator 把内容裁掉 | `lib/screens/input/free_search_screen.dart` `_searchBar`(:837):容器只给 `minHeight: 46`、文字行高 1.35、`contentPadding` 上下各 12 → 内高 ~41.6px 装得下 13px 字号整行 | `find-material-impl-free-input.png` |
| 4-② | 筛选区默认全展开、悬置挡大半屏、无法收起 | 4 行 chip 常驻在 Column 顶部,没有收起态 | 同文件 `_filterBar`(:945):收起态一行「筛选(n) + 已选条件摘要 chips + 清空」;`_filterPanel`(:1103)展开为**限高 42% 可滚动**的面板 + 「收起筛选」;`_runSearch` 开始/结束都置 `_filtersOpen=false`(:`_runSearch`) | `find-material-impl-free-filters.png`(展开)、`find-material-impl-free-empty.png`(默认收起) |
| 4-③ | 没找到原文只给无关的"真实材料" | 空结果只有"再搜一次",没有解释也没有保底内容;AI 检索链路与"自由搜"是两条腿 | 空结果卡 `_emptyAfterRun`(:1581):用**真实检索信息**说清关键词/检索源/原始命中条数/筛选后 0 条/源说明;`_aiEntryCard`(:1666) → `_generateAiRewrite`(:691) → `_aiResultCard`(:1814) | `find-material-impl-ai-empty.png`、`find-material-impl-ai-generated.png` |
| 5 | 材料卡普遍不显示封面(能爬到就展示) | 检索结果大多没有 `imageUrl`,卡片"有图才显示"→ 永远文字版式 | `lib/widgets/material_result_list.dart`:卡片封面位 `_MaterialResultCardCover`(:908) 取图顺序 ①数据自带 → ②Gutenberg 按书号现算(零网络) → ③**卡片级懒加载** og:image(`MaterialCoverProbeCache` :462 + `httpMaterialCoverProbe` :545,内存缓存/并发 3/失败静默);`material_result_list.dart:709` `enableLazyCoverFetch`(默认 true,测试可关) | `find-material-impl-cover-with.png` / `find-material-impl-cover-without.png` |

### 14.2 AI 改写学习版(非原文)链路

- 服务:`lib/services/material_ai_rewrite.dart`(新)
  - 标注常量 `aiRewriteMarker`(:39)/ `aiRewriteLicense`(:42);
  - 提示词纯函数 `buildAiRewritePrompt`(:287):只喂**过滤前**真实线索(标题/site/kind/摘要/url,≤8 条)+ 难度档 + 目标/兴趣/屏蔽项;硬规则:不许编链接/作者/数据、明确改写非原文、英文 3~4 段目标词数、只输出 JSON;
  - 解析纯函数 `parseAiRewrite`(:344):容错围栏/别名字段;正文必须英文且 ≥80 词;`used_sources` 只映射**真实候选编号**(模型编的 URL 一律丢);不足 2 条线索时 `basisLimited=true`(界面明说依据有限);
  - 来源与许可 `buildAiRewriteProvenanceText`(:496):正文末尾保留来源清单链接 + 非原文说明 + license;
  - 入库行纯函数 `buildAiRewriteMaterialRow`(:526):`source='ai'`、`title` 带「AI 改写学习版（非原文）」、`license` 标注、`url` 保留首条真实来源、`difficulty_json` 用真实分析;
  - 执行器 `MaterialAiRewriter`(:599):handler/measurer 可注入(默认 `DeepseekApiService.completeJson(thinkingLevel: output)` + `MaterialLibrary.analyze` 量真实字数/覆盖率);失败返回人话原因,不抛到界面;
  - 入库 `MaterialAiRewriteStore.ingest`(:673):先本地算难度再写材料库(1 个 chunk),返回 materialId。
- 界面:`free_search_screen.dart` `_aiEntryCard` / `_aiResultCard` / `_useAiMaterial`(:730)
  - 有原文 → 原文在上,AI 块在下方以不同底色「这些都不合适?」+「AI 改写 · 非原文」tag,**不自动生成、不替换**;
  - 无原文 → 「没找到想读的原文?」为主路径;零线索时按钮禁用并说明不凭空编;
  - 生成后展示:标注 + 真实字数/覆盖率/CEFR/时长 + 「基于 N 条真实来源」+ 开始读/保存到我的/重新生成;
  - 开始读/保存到我的都先 `MaterialAiRewriteStore.ingest`,再进 `MaterialReaderScreen` 或记 `MaterialChannelStore.addSavedMaterial(free:<词>, id)`。

### 14.3 本轮测试与渲染

| 文件 | 用例数 | 结果 |
|---|---|---|
| `test/find_material_ai_rewrite_test.dart` | 21 | 全绿(纯函数 + 注入 handler/measurer) |
| `test/material_result_list_test.dart` | 21(新增 6 条封面) | 全绿 |
| `test/find_material_free_search_test.dart` | 12(输入框/筛选收起/AI 保底/回归) | 全绿 |
| `test/find_material_render_test.dart` | 17(出图 17 张) | 全绿 |
| `flutter analyze --no-pub lib` | — | 0 error / 0 warning |
| `test/ui_copy_lint_test.dart` | 1 | 全绿(新文案无 Markdown 星号) |

新增/刷新渲染(docs/ui-preview/real/):`find-material-impl-free-input.png`、
`find-material-impl-free-filters.png`、`find-material-impl-cover-with.png`、
`find-material-impl-cover-without.png`、`find-material-impl-ai-empty.png`、
`find-material-impl-ai-generated.png`,并重渲染原有 11 张(自由搜空态/结果/页码、
按需找面板/结果/页码/缺数据、入口、历史、无封面卡)。

### 14.4 纪律自检

- 封面**绝不画假封面**:抓不到就保持文字版式;懒加载失败静默且缓存负结果;渲染测试注入"抓不到"实现,不靠网络;
- AI 改写**绝不冒充原文**:标题/license/tag/正文末尾四处固定标注;模型编的来源 URL 丢弃;没有线索就不生成;
- 数字**全是本地实数**:字数/覆盖率/CEFR/时长来自 `MaterialLibrary.analyze`,不用模型自报的数字;
- 无新依赖、无 DB 结构变更、无 dbVersion 改动;未 commit。
