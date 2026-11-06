# QA 实施度复核 · 找材料（A 方案）· 2026-11-07 00:2x

> 复核对象：find-material 交付（task-8）。基准：`docs/QA-IMPLEMENT-CHECKLISTS.md` §2 F1–F13 + 设计
> `FIND-MATERIAL-REDESIGN-2026-11-06.md` §2A/§3 + `IMPLEMENT-PLAN-2026-11-06.md` §2.2 + Lead 裁决 D4/D6。
> 方法：代码追到真实调用（不只看 UI）→ 11 张渲染逐张 `read_image` → lockrun 定向测试 → grep 占位/假数据 → 快照/历史 Hive 写入核。
> 结论：**P0 = 0，F1–F13 全部通过**；4 条 P3 记档（不阻塞本主题，但建议收尾前处理 2 条）。analyze 归因见 §四。

## 一、实测数字（本次跑，非转抄）

- 测试：`bash tool/lockrun.sh test test/find_need_context_test.dart test/material_result_list_test.dart test/material_hub_test.dart test/material_channel_paging_test.dart test/material_channel_render_test.dart test/find_material_render_test.dart --no-pub`
  → **+52 All tests passed**（含频道页渲染出图），与交付声明一致。
- 渲染：`docs/ui-preview/real/find-material-impl-*.png` **11 张齐全**（00:16 生成），逐张看过，见 §二。
- analyze（我 23:5x 跑的一次，Lead 后续会再跑）：find 相关仅剩 **2–3 条风格 info**（`find_material_screen.dart:339/664/745` 类），无 error/warning；`find_need_context.dart`/`material_result_list.dart` 无问题。G6 最终门禁要求 0 error/0 warning（info 不强制，但风格 info 建议清）。

## 二、逐条复核（F1–F13）

| ID | 结论 | 证据（file:line / 渲染 / 测试） |
|---|---|---|
| F1 入口页 | ☑ | `find_material_screen.dart`：34px 标题+副标（`find-material-impl-entry.png` 实看）；两张**等宽**大卡（`Row`+两个 `Expanded`，同高）；卡内真实值：左「上次搜过 climate change」来自 `FindSearchHistory.load()`，右「i+10 / 四六级 / 时态 / 已掌握 4,200 词」来自 `FindNeedContext`；右上 `[历史]` 可点（同上图）。生产构造 `FindMaterialScreen()` 无参（center:250），注入参数仅测试用。 |
| F2 最近搜过 + 上次结果卡 | ☑ | 渲染：3 个 chips + 「搜索历史 · 可清空」+「上次找的结果还在 · 18 篇 · 2 分钟前 / 继续看 →」。代码：`find_material_screen.dart:85` `MaterialChannelStore.loadSnapshot('need:all')` 真读快照；chips 点一条 → `FreeSearchScreen(initialQuery:)`（:108）。P3 注：入口的「上次结果卡」只读 `need:all`（自由搜的是 `free:<词>` 快照，不进入口卡）。 |
| F3 自由搜输入/筛选 | ☑ | 渲染 `free-empty/free-result` 实看：搜索框（回车即搜）+ **9 个真实来源**（5 个带「实测可用」标）+ **5 类型**（书籍/论文/外刊新闻/播客/百科 = W1 已修）+ 4 难度（文案「按来源预估,非精确覆盖率」，不假冒真实难度）+ 4 场景。代码：`free_search_screen.dart:200` 真传 `sourceIds:`，`:217` 难度过滤 `_bandMatches`，`:292-304` 场景取 taxonomy queries，`:171-180` 难度用 `MaterialLibrary.estimateDifficulty`（来源级预计，诚实用语）。 |
| F4 搜索执行/过程折叠/结果 | ☑ | `_runSearch` → `OriginalSearch.search(...)`（`free_search_screen.dart:160-164` 起）；过程卡 `_processCard` 跑完收起（渲染 free-result 无过程卡）；空结果有「再搜一次」（`free-empty-result.png`）；黑名单过滤 `_runSearch:181-188` 走 `InputPreferences.allowsMaterial`。 |
| F5 按需找 4 行依据 | ☑ | 渲染 `need-panel/need-empty` 实看：难度档「i+10·挑战区」/学习目标「四六级·兴趣阅读」/弱项「语法:时态 8 次·冠词 5 次」/最近阅读「近 30 天读完 4 篇·180 词/分」；无数据版全部「待测 · 怎么测」，**无任何数字**。代码：`find_need_context.dart:170-214` 每行指回真实字段（MaterialPrefs/InputPreferences/TutorDashboard.errorTagCounts/materialsFinished30d+readingWpm），`:163` 注释与 `:179/:189/:204` 分支保证 measured=false 不出数字。 |
| F6 「为什么推这些」两级 | ☑ | 级别 1：`need-panel` 渲染「按 i+10 档、对准目标 四六级、兴趣阅读 挑材料…已避开你屏蔽的:影视娱乐」（`find_need_context.dart:217-249`）。级别 2：`need_search_screen.dart:294-305` `_reasonFor` **`analysis?.knownTokenRatio == null` 直接 return null**；`need-result` 渲染中每张卡只有算出覆盖率（90%/96%/97%）后才出现「为什么推:难度 X% · 落在你选的 i+10 · 命中目标「四六级」」→ 与设计硬约束一致。 |
| F7 共用结果件（分组/分页/封面/动作/继续找更多/回顶） | ☑ | 渲染 `free-result/free-pager/need-pager`：组头「教材 1 篇 / 应试真题 2 篇」、页脚「第 1/2 页 · 共 13 篇 · 每页 10 条」、首末禁用、`继续找更多`；无封面卡见 `no-cover.png`（纯文字版式，明示「没有抓到 og:image → 不画渐变假封面」）。代码：`material_result_list.dart` 页码 `hasPrev/hasNext`（:798-799/809/839）、三动作回调（:978-983）、保存走 `MaterialLibrary.ingestText`（:1339）+ `addSavedMaterial`（:1223）、打开原文 `launchExternalUrl`（:1244）；**切页回顶**在页面侧 `free_search_screen.dart:405` / `need_search_screen.dart:247` `_scroll.jumpTo(0)`（`onPageChanged` 内）；继续找更多追加后跳第一条新结果页（`material_result_list.dart:1134`）。 |
| F8 条件条/元信息/成本口径 | ☑ | 渲染：自由搜顶部搜索框+筛选条固定、结果区「本次结果·13 篇·第 1/2 页」；按需找页顶「你的情况」卡 +「改需求」；成本文案「官方搜索约 X 元(模型未计)」风格与频道页一致（`free_search`/`need_search` 的 metaRow，`need_search_screen.dart:694-714` 区域）。 |
| F9 快照复用（free:<词>/need:all） | ☑ | `free_search_screen.dart:91/145` `storeId: 'free:<归一关键词>'`；`need_search_screen.dart:59` `MaterialResultController(storeId:'need:all')`；读写走 `MaterialChannelStore.loadSnapshot/saveRun`（`material_result_list.dart:1070-1145`），**未新增表/依赖/Hive key 体系**。 |
| F10 接线/旧入口/文案 | ☑ | 材料中心 3 处入口全指新页：`material_center_screen.dart:247-256 _openFindMaterial`、`:331 onOpenNeed`、`:406/:509 tune_rounded`；hub 文案「找材料」（`material_hub_home_view.dart:240/655`）；taxonomy need 改名（`material_taxonomy.dart:68`）。旧 `MaterialBrowseScreen` 只剩 settingsOnly 用途（channel:1435 去设置需求、need_search:278 改需求，符合 P2-8/D 规定）。 |
| F11 学习助理数据真实/只读 | ☑ | `find_need_context.dart:56-110` 组装 `MaterialNeed/InputPreferences/LearnerModelStore/TutorSnapshotService`，任何一块失败降级；文件内**唯一写入**是搜索历史（`FindSearchHistory.remember` 复用 `MaterialPrefs.rememberQuery`、`clear` 写回同一 Hive key，:366-373），`FindNeedContext` 本体无写偏好/模型。 |
| F12 频道页薄委托、行为零变化 | ☑ | 频道页保留自有行为（`_startDiscovery` @:803、`_loadMine` @:681、`saveRun` @:935、`_refreshAtCap` @:1476+ 全在）；仅渲染层改调公共件：`MaterialResultPageBar`(:2227)/`MaterialResultGroupHeader`(:2235)/`groupMaterialResultItems`(:2244)/`MaterialResultCard`(:2261)/`MaterialResultCoverThumb`(:2435)。回归：`material_channel_test` 35 + `material_channel_paging_test` 7 + `material_channel_render_test` 全绿（含 4+1 张图重出）。 |
| F13 交付物 | ☑ | 对照表 `docs/FIND-MATERIAL-IMPLEMENT.md` 存在且与代码基本一致（需把 §0 的「频道页 ✅/回归 ✅」按本次复核更新为"薄委托"表述）；11 张 `find-material-impl-*.png` 齐全；单测 `find_need_context_test`(8) + `material_result_list_test`(14) 全过；**52 passed** 实测。 |

## 三、P0 / P2 / P3

**P0：无。**

P3（记档，前 2 条建议收尾前处理）：
1. **旧 AI 找材料链路仍有 5 个入口**（`input_home.dart:161`、`material_browse_screen.dart:270`、`category_material_screen.dart:833`、`material_category_screen.dart:210`、`legacy_material_center_screen.dart:1459` → MaterialDiscoverScreen）。设计 §9 明确"是否下线需用户确认"，故不判失败；但用户会看到两套 AI 找材料入口，建议把「需要用户确认下线」写进交付说明/下一轮任务。
2. **风格 info 待清**：`find_material_screen.dart` 约 2–3 条 info（use_null_aware_elements/prefer_function_declarations/unnecessary_underscores），最终 `final_gate` 前清掉（G6 硬门禁只管 error/warning，但别留到发版）。
3. 入口「上次结果卡」只读 `need:all` 快照，自由搜的 `free:<词>` 上次结果不显示在入口（设计未强制，用户可能期待"上次找的"包含自由搜）。
4. 过期注释：`free_search_screen.dart:24` 仍写"类型:书籍/论文/外刊(3 类)"，实际 5 类（W1 已修），改注释即可。

## 四、analyze 归因（本主题部分）

- find 相关：`find_material_screen.dart` 2–3 条风格 info；`free_search_screen.dart`/`need_search_screen.dart`/`find_need_context.dart`/`material_result_list.dart` 无 error/warning。
- 与 find 无关的 error（output WIP `practice_flow_screen`）不计入本主题；最终门禁由 Lead 全量 analyze 复核。

## 五、结论

**找材料 A 方案：通过（P0=0）**。设计 13 条全部落地且有代码/渲染/测试三重证据；11 张渲染逐张核过（含 free-result 无裁切、need-empty 无数字、no-cover 无假图、history sheet 单拖拽条）；三动作/切页回顶/继续找更多/快照/历史清空均为真实接线。可进入集成；P3 前 2 条建议随收尾处理。
