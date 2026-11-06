# QA 实施度清单（本轮验收基准）· 2026-11-06 深夜

> 用途：qa-verify 拿这份清单逐项打勾；**任何 ☐ 未落地 / 假实现 / 占位 = P0 退回**（IMPLEMENT-PLAN §0）。
> 来源：`docs/IMPLEMENT-PLAN-2026-11-06.md` §0/§2 + 四份设计文档（READER-REDESIGN §3/§4/§7、
> FIND-MATERIAL-REDESIGN §2A/§3、ASSISTANT-MINE-REDESIGN §2A/§2B/§3.2/§4、OUTPUT-REDESIGN §一/§二/§四）+ `docs/ACCEPTANCE-2026-11-06.md`。
> 状态图例：☐ 未实现 · ◐ 实现中/部分 · ☑ 已交付待 QA 复核 · ✗ QA 退回（P0）。
> 快照：2026-11-06 23:25（reader 未开工、无新文件；find 公共件 `lib/widgets/material_result_list.dart` 已出现 → D4 已解；assist `lib/services/tutor_briefing.dart` 已出现；output 未开始；上一轮 material-fix 已交付 5 张图 + 分页测试，抽查见 §5）。
> 判定纪律：① 每条必须有 file:line 或可复现命令；② 渲染图必须用 `read_image` 逐张看过内容，不看文件名；
> ③ "测试绿"不等于实现对；④ 不许拿一张代表图当逐屏交付。

## 0. 通用闸门（四主题都过；任一不过 → 该主题整体 P0）

| ID | 判据（可验证） | 验证方式 | 状态 |
|---|---|---|---|
| G1 | 交付 `docs/<主题>-IMPLEMENT.md` 对照表：**每条设计项 → 实现 file:line → 渲染图文件** | 文件存在 + 逐行抽 5 条回查代码 | ☐ |
| G2 | 无 TODO / FIXME / 占位文案 / 「后续再做」/ 写死假数据（演示数值硬编码在 UI 层） | `grep -rn "TODO\|FIXME\|占位\|后续" lib/<主题目录>`；读代码找 `'示例'`、写死数字 | ☐ |
| G3 | 所有按钮/入口/返回/持久化真接线（点得动、有真实行为、返回路径对） | 逐屏点验 + 读 onTap/onPressed 实现 | ☐ |
| G4 | 逐屏真实渲染，**不是一张代表图**：390×844@3x、真字体（NotoSansSC）+ 真图标（MaterialIcons） | 张数 ≥ 设计屏数；`read_image` 逐张核内容 | ☐ |
| G5 | 新交互有 widget test 或纯函数单测；**旧测试无回归** | `bash tool/lockrun.sh test test/<相关> --no-pub` 记录数字 | ☐ |
| G6 | `bash tool/lockrun.sh analyze --no-pub lib` = 0 error / 0 warning（存量 info 不算） | 贴原始输出行 | ☐ |
| G7 | 文件所有权：diff 里不出现写作用域之外的文件（IMPLEMENT §1.1） | `git status --short` + 逐文件对照作用域表 | ☐ |
| G8 | 不改 pubspec / 不加依赖 / 不改 dbVersion / 不 commit / 数据库只写现有列 | `git diff pubspec.yaml`；`grep dbVersion`；`git diff lib/services/database.dart` | ☐ |
| G9 | flutter 命令全部走 `bash tool/lockrun.sh`（并发直跑会静默失败） | 交付汇报里的命令原文 | ☐ |
| G10 | 空态/加载/错误三态齐全且同一套长相（不允许裸 Text+按钮的重试） | 逐屏点验 empty/loading/error | ☐ |
| G11 | 深色模式至少不崩（本轮可二期视觉，但不能因为没做而少功能） | 切深色过一遍主路径 | ☐ |

## 0.2 跨主题依赖/决策项（**Lead 已裁决，按此验收**）

| ID | 裁决（已生效） | 验收口径 |
|---|---|---|
| D1 | 阅读器新令牌**批准局部文件** `lib/widgets/reader_tokens.dart`，**不进** `lib/config/*` 全局主题 | 文件存在且被阅读器引用；色值按设计：冷灰纸 `#EEEFEA`、砖红 `#B23A2C`、近黑 `#15181A`/次要 `#494F51`/极淡 `#8C918F`；对照表登记 |
| D2 | 助理暖色 flavor **批准局部常量**（`lib/screens/tutor/tutor_theme.dart` 或 tutor/profile 目录内），不改 `v4_theme.dart` | 色值按 ASSISTANT §2.2（`#FBF7F0`/`#211C16`/`#6C6259`/`#A0968A`/`#EDE3D5`/`#C4562E`/`#2F5D50`）；`git diff lib/config/` 应为空 |
| D3 | 输出 4 个纸面件：**2026-11-07 01:4x Lead 裁决（记录）**——实际落地 `lib/screens/output/widgets/paper_kit.dart` + `Paper*` 命名（PaperLevelTabs/PaperRow/PaperSectionHead/PaperSourceLine）**可接受、不必改名**；理由：输出局部、未污染全局 v4_kit/design_tokens，`Paper*` 比 `V4*` 更准确（描述"纸面族"）。原「`output_kit.dart` + `V4*`」要求作废 | 文件存在；`PaperLevelTabs`/`PaperRow`/`PaperSectionHead`/`PaperSourceLine` 四类均被真实引用；`git diff lib/widgets/v4/` 应为空（已核对：空） |
| D4 | **已解**：`lib/widgets/material_result_list.dart` 已由 find 落地 | 频道页改调公共件且行为不变（见 F12） |
| D5 | 米黄/墨夜 hex 由实现自定并在 `docs/READER-C-IMPLEMENT.md` 对照表登记 | **验收按对比度硬指标**：正文 ≥ **4.5:1**、译文/次要文字 ≥ **3:1**，纸白/米黄/墨夜三纸都要过；不按"好看" |
| D6 | 找材料 `[历史]` **必须实现**，不许静默砍：底部/页面 sheet 列 `MaterialPrefs` 搜索历史（可清空、点一条回填） | 入口可点 + 历史真实来自 `MaterialPrefs` + 清空生效 + 点一条回填搜索词；已通知 find 实施 |

## 1. 阅读器 = C + 纸张三色 + 真实进度%（task-7）

> 设计：READER-REDESIGN §4（C 版面）全集 + §3（B 的纸张三色）+ §7（进度%实现路径）+ IMPLEMENT §2.1 九条。
> **QA 复核（终版，2026-11-07 02:3x）：R1–R15 全部 ☑（下表状态列以本行为准）；P0=0，剩 2 条 P3。
> 实测：6 个测试文件 lockrun **56 passed**；13 张图逐张 read_image；analyze（lib/screens/input + lib/widgets）= 0 error/0 warning/**6 条存量 info**（process_chat×5 + ai_article_section×1，均非本主题文件）。
> 查词弹层布局未重排属已批准作用域例外（§7.2）；设计外增项 5 条已在对照表 §6 写明。详见 `docs/QA-IMPLEMENT-reader.md`。**

| ID | 设计出处 | 必须实现项（可验证判据） | 生产文件 | 状态 |
|---|---|---|---|---|
| R1 | §4 配色 | 页面纸底 = 冷灰纸 `#EEEFEA`；近黑 `#15181A`/次要 `#494F51`/极淡 `#8C918F`/线 `#D7D9D2`；**唯一强调**砖红 `#B23A2C`（除砖红外不得出现第二个彩色强调） | reader screen + 令牌 | ☐ |
| R2 | §4 字阶 | 标题 **28/1.1/w900/letterSpacing -0.8**；栏目标签 **9.5/1.3/+1.6**；署名 **10.5/1.4/+0.3**；首段 **20/1.82**；其余正文 **18/1.8**；译文 **13.5/1.8**（6 档都要能在代码常量里找到，不是随手写） | reader screen/reader_text | ☐ |
| R3 | §4 刊头 | 「刊头双线」= 顶部 2px 粗线 + 1px 细线（两行都在正文滚动内容顶部） | reader screen | ☐ |
| R4 | §4 零常驻按钮 | 底部默认**没有任何图标按钮/FAB**；只有：贴底 **2px 进度线** + **42px 把手区**（左 `N%` / 中间 **36×4** 抓手 / 右「上滑工具」hint） | reader screen + 新进度组件 | ☐ |
| R5 | §4 右侧进度 | 右侧悬浮 `N%` 胶囊（10.5/w800，白底 0.92 + 边框）+ **96px 竖轨道（3px 宽，砖红填充）**；正文右侧内边距为它让位（设计 46，允许实现微调但必须有让位） | reader screen | ☐ |
| R6 | §4 控制台 | 上滑「阅读控制台」**4 组**：(a) 进度卡：`已读` + `第 N 段 / 共 M 段` + **34px 数字** + `继续阅读` + 3px 进度线；(b) 学习：**3 个等宽方块**（翻译 / 追问 / 收词 12）；(c) 目录：**3 行紧凑行**（序号 + 节名 + 本节 %）；(d) 材料：字号与行距 / 模型与思考档 / 导出·听写·读完 | 新 reader_console + reader screen | ☐ |
| R7 | §4 弹层 | 目录 / 阅读设置 / 查词 / 材料弹层全部按 C 重排（组标题 10/w800/+1.2 + 控件；不允许旧「大字裸列表」） | reader screen | ☑（设置/目录/模型/材料动作/续读/收词/翻译均已重排；**查词=共享件仅跟随纸色、布局未重排**，§7/§7.2 已写明且 Lead 批准例外） |
| R8 | IMPLEMENT §2.1-8 | 翻译进度**不再压正文**（收进控制台或顶部细条）；开翻译时底部不得多出灰带 | reader screen | ☐ |
| R9 | IMPLEMENT §2.1-6 | 纸张三色：**纸白（默认）/米黄/墨夜**；设置里有 3 个色卡 + **实时预览卡**（正文 14.5/1.7 + 译文 12/1.7）；三纸都要可读（正文对比度 ≥4.5、译文底/选中态/进度线可见）；切换**立即生效**、**重启保留**（Hive reader_settings） | reader screen + reader_settings | ☐ |
| R10 | §7 / IMPLEMENT §2.1-7 | 真实进度%：`ValueNotifier` 只重建进度组件（**不许 setState 整屏**）；`_onScroll` 更新；落库 `percent = 滚动真实比例`，**未读完 ≤99、finished 才 100**；续读按 percent 跳；书架/材料中心读到同一个值 | reader screen + database 调用 | ☐ |
| R11 | IMPLEMENT §2.1-9 | 旧功能回归 11 项：翻译范围 / 保存位置 / 进度落盘 / 书架 / 收藏 / 追问 / 阅读设置 / 目录 / 丰富形式 / 长按选词 / 生词高亮 / 图片 / PDF 兜底（逐项点验，不许"功能没了"） | reader screen 全量 | ☐ |
| R12 | IMPLEMENT §2.1 验收 | 新增 widget test ≥4：控制台上滑、纸色持久化、进度更新（notifier 有值且不整屏 setState）、底部零常驻按钮；测试**不许挂起**（不许 pumpAndSettle 死等/真实 I/O） | test/reader_c_* | ☐ |
| R13 | IMPLEMENT §2.1 验收 | 逐屏渲染 **≥8 张** `reader-c-*.png`：首屏 / 上滑控制台 / 纸白 / 米黄 / 墨夜 / 目录 / 设置 / 查词 / 翻译进行中（按实际屏数 ≥8，缺一即 P0） | docs/ui-preview/real/ | ☐ |
| R14 | IMPLEMENT §2.1 验收 | `docs/READER-C-IMPLEMENT.md` 对照表：设计条目 → file:line → 渲染图；**9 条清单逐条打勾**（IMPLEMENT §2.1 的 1~9） | docs/ | ☐ |
| R15 | 反向约束（§5.5） | 不许把 V4 全局 `AppFont` 字阶改掉（阅读排印字号只活在本页/ReaderSettings）；不许恢复玻璃底栏；不许改其它屏幕 | git diff 核对 | ☐ |

## 2. 找材料 = A（task-8）

> 设计：FIND-MATERIAL §2 方向 A + §3 共用规格 + §7 复用/新增；IMPLEMENT §2.2 七条。

> **QA 复核结论（2026-11-07 00:2x）：F1–F13 全部 ☑，P0 = 0**；证据见 `docs/QA-IMPLEMENT-find-material.md`（11 张渲染逐张核 / 52 passed 实测 / 三动作与快照真接线）。遗留 P3×4 已记在该报告 §三。

| ID | 设计出处 | 必须实现项（可验证判据） | 生产文件 | 状态 |
|---|---|---|---|---|
| F1 | §2A 首屏 / IMPLEMENT 2.2-1 | 入口页标题 **34px/w900**；**两张等宽大卡**（自由搜 / 按我的情况找）；卡内放**真实值**：上次搜过（`MaterialPrefs` 历史）、难度档、目标、基线词数；右上 `[历史]`（D6 已裁决必须做） | find_material_screen.dart（新） | ☑ |
| F2 | §2A 首屏 | 「最近搜过」chips（真实历史、可清空）；「上次结果卡」读**快照 real 数据**（组数/篇数/时间），点击继续看 | find_material_screen + MaterialChannelStore | ☑（P3：入口卡只读 need:all） |
| F3 | §2A / §3.3 | FreeSearchScreen：单行搜索框**回车即搜**；空关键词给推荐检索；筛选齐全：来源（9 源）/类型（5 类，W1 已修）/难度（来源级预计、诚实用语）/场景；语言=英文如实标注 | free_search_screen.dart（新） | ☑ |
| F4 | §3.3 / IMPLEMENT 2.2-2 | `OriginalSearch.search` 执行；**搜索过程折叠**；结果进共享结果件；空结果「再搜一次」；黑名单真过滤 | free_search_screen | ☑ |
| F5 | §3.1/§3.2 | NeedSearchScreen **4 行真实依据**（难度档/目标/弱项/最近阅读，指回真实字段）；缺数据降级「待测 · 怎么测」**不显示数字** | need_search_screen + find_need_context（新） | ☑ |
| F6 | §3.2 | 「为什么推这些」两级：级别 1 搜索前；级别 2 **必须补抓正文算完覆盖率才出现**（analysis 空 → 不显示） | need_search_screen | ☑ |
| F7 | IMPLEMENT 2.2-4 / §3.4 | 共用 `MaterialResultList`：类型分组 / 每页 10 条 / 页码控件（首末禁用）/ 真封面才画图（否则 TextCover）/ 三动作 / 继续找更多（追加+页数增加）/ 切页回顶 | material_result_list.dart（新） | ☑ |
| F8 | §3.4 | 结果页固定条件条（可「改条件」）；元信息含篇数/页码/花费口径（官方搜索约 ¥X，模型未计） | 两个结果页 | ☑ |
| F9 | IMPLEMENT 2.2-7 | 快照 `free:<归一关键词>` / `need:all` 复用现有 store；**不新增表/依赖/Hive key 体系** | 结果页 + material_channel store | ☑ |
| F10 | IMPLEMENT 2.2-5 | 材料中心「找材料」卡 + 顶部 tune → 新入口页；旧 `MaterialBrowseScreen` 入口下线（仅 settingsOnly 用途保留）；文案改「找材料」 | center / hub_home_view / taxonomy | ☑ |
| F11 | IMPLEMENT 2.2-3 | 学习助理数据来源真实（§3.1 table 可核对）；`FindNeedContext` **只读**（唯一写=搜索历史复用 MaterialPrefs key） | find_need_context.dart | ☑ |
| F12 | IMPLEMENT 2.2-6/§9 | 频道页抽公共件后**行为零变化**（自有 _startDiscovery/_loadMine/saveRun 保留，仅渲染层薄委托）；paging/render/channel 测试绿 | material_channel_screen（薄委托） | ☑ |
| F13 | IMPLEMENT 2.2 验收 | 单测 FindNeedContext 降级 + 筛选/分页；渲染 11 张齐全；对照表交付；**52 passed 实测** | test/ + docs/ | ☑ |

## 3. 助理 / 我的 = B 主语言 + A 数据内页（task-10）

> 设计：ASSISTANT-MINE §2.2（B 每日简报完整规格）+ §2.1（A 诊断台）+ §3.2（共同必做）+ §4（数据来源）+ §6（实现计划）；IMPLEMENT §2.3。
> **QA 复核（终版，2026-11-07 01:5x）：M1–M14 全部 ☑（M13 附 Lead 已知情 backlog：tutor_chat 7 处裸字号）+ 额外返工项 M15 名片整卡重排 ☑；P0=0、P1×3 全关（Ahem 方块字/周报假 0/名片）；剩 3 条 P3。38 passed 实测、16 图逐张复核。详见 `docs/QA-IMPLEMENT-assist-mine.md`。**

| ID | 设计出处 | 必须实现项（可验证判据） | 生产文件 | 状态 |
|---|---|---|---|---|
| M1 | §2.2 助理首页 | B「每日简报」：`THURSDAY BRIEF` 眉标（9.5/800/字距1.6）+ **40px 日期** + 22/w800 问候 + 时间线（点+竖线，含分钟与任务）+ 墨绿 3px 竖线引文 + 砖红胶囊主 CTA；暖纸底 `#FBF7F0`、暖墨 `#211C16/#6C6259/#A0968A`、线 `#EDE3D5`（见 D2） | tutor_home.dart | ☐ |
| M2 | §2.3 数据来源 | 助理首页数据全部来自 `TutorDashboard`（`tutor_snapshot.dart:73`；字段 §4.3 表），**不新 SQL、不新 AI 调用**；"约 22 分钟"必须有 `todayTasks` 求和的真实分母 | tutor_home + tutor_briefing | ☐ |
| M3 | §2.2/§4.6 | `TutorBriefing.build(TutorDashboard)` 纯本地模板（headline/timeline[3]/yesterday/reminder），~150 行 + **单测**（含空数据降级，不造数字）；当前 `lib/services/tutor_briefing.dart` 已出现 → 待验内容与接线 | lib/services/tutor_briefing.dart（新） | ◐ |
| M4 | §2.2 我的首页 | 我的首页按 B 重做：本周报告入口 + 今日/本周事实（数字来自 §4.1/§4.2 真实来源）；信息架构：数据入口 > 配置入口（P8） | profile_home.dart | ☐ |
| M5 | §2.1 / IMPLEMENT 2.3-2 | 数据内页 A 诊断台：**至少 3 屏**按 A 的 KPI 带（白卡 3 列）+ 五维细条（3px）+ 环（54px）重排：`stats_page`（学习统计）/ `weekly_report_screen`（本周报告）/ `error_archive_screen`（错误档案）；复用现成 `SparkBars`/`RadialGauge`/`StudyCalendar`，不新造图表 | 3 屏 | ☐ |
| M6 | §1.2 / §6 阶段1 | **12 个裸 AppBar 全部换 `V4JellyAppBar`**（逐项勾）：① stats_page:55 ② weekly_report:263 ③ error_archive:186 ④ api_settings:542 ⑤ appearance_screen:31 ⑥ backup_screen:264 ⑦ bookmarks_screen:488 ⑧ widget_settings:85 ⑨ placement_test:310 ⑩ tutor_chat:467 ⑪ tutor_interview:257 ⑫ writing_logs:76；交付时逐条打勾并给 file:line | 12 文件 | ☐ |
| M7 | §3.2-2 | 边距统一 `Insets.page`：`weekly_report_screen.dart:292`(12)、`error_archive_screen.dart:197`(16)、`writing_logs_screen.dart:119`(16) 等裸数值清零 | 上述文件 | ☐ |
| M8 | §3.2-3 | 字阶统一 `AppFont`：`weekly_report_screen.dart` 11 处 `bodySmall/labelSmall` 裸用清零（同屏不许两套元信息字号） | weekly_report | ☐ |
| M9 | §3.2-4 | 空态统一：4 种长相（`AppEmpty`/`EmptyState`/`ChartEmptyHint`/裸 Text+按钮）收敛成 1 种，且 loading/empty/error 三态齐 | 相关屏 | ☐ |
| M10 | §6 阶段2 / IMPLEMENT 2.3-4 | 助理**任务详情页**（新页，替代 `tutor_home.dart:1044-1123` 的 showModalBottomSheet）：必须有 reason / 开始·完成·跳过·撤销·编辑 / `target_minutes` / `goalTag` | 新页 | ☐ |
| M11 | §6 阶段2 | 助理**复盘页**（新页，替代 `tutor_home.dart:431-436` 页内卡）；数据用 `TutorReview.lines/metrics`（§4.3），空复盘要给空态 | 新页 | ☐ |
| M12 | §4.5 / P9 | 我的补**写译记录入口**（页面已有，`writing_logs_screen.dart`；入口现在只在 output；`profile_home.dart:174-223` 加入口） | profile_home | ☐ |
| M13 | §3.2 / 验收 1~6 | 通用验收：有主题色/不白底一片；主次分明；三态齐；颜色/圆角/字号/间距走 tokens（`rg 'fontSize: [0-9]' lib/screens/profile lib/screens/tutor` 只剩 tokens 调用，允许少量局部常量并有注释）；`rg 'AppBar\(' lib/screens/profile lib/screens/tutor` **应为 0**；深色可用 | grep + 逐屏 | ☑（AppBar=0；api_settings 3 处已收口；tutor_chat 7 处 = Lead 已知情 backlog） |
| M14 | IMPLEMENT 2.3 验收 | 交付：`docs/ASSISTANT-MINE-IMPLEMENT.md` 对照表（12 内页逐项 + 设计条目→file:line→渲染图）；渲染 **≥12 张** `assist-mine-impl-*.png`（助理首页/任务详情/复盘/我的首页/统计/周报/错误档案/学习偏好/API设置/写译记录/备份/关于）；单测 TutorBriefing+空态；现有 tutor/profile 测试全绿 | docs/ + test/ | ☐ |

## 4. 输出 = A 纸面 + 入口借 B 头图 + 来源修复 + 四六级分桶/拆目标（task-9）

> 设计：OUTPUT-REDESIGN §一（P0-1 根因/修法 S1~S5）、§二（P0-2 三层根因/分桶 P1·P1.5·P2）、§四A（纸面工作台）、§六（落地顺序）；IMPLEMENT §2.4。
> **QA 复核（终版，2026-11-07 02:0x）：O1–O18 全部 ☑（O13 经 P2-1 闭环：resolveExamType 筛选优先+透传+3 单测）；P0=0、P1=0、P2 全关，剩 2 条 P3。18 个输出相关测试文件实测 265 passed；9 图复核（home 空白已消/write、plan 真重排/两处 PaperRow 落地）。最终状态=通过，可进集成。详见 `docs/QA-IMPLEMENT-output.md`。**

### 4.1 视觉 A

| ID | 设计出处 | 必须实现项（可验证判据） | 生产文件 | 状态 |
|---|---|---|---|---|
| O1 | §四A | 四阶设置页：极细工具行（无 AppBar 底色）+ 30/w900 主标 + 等级筛选行 + 编号区块（`01 ── 推荐来源 ── 3 份` 细线计数）+ 白面 1px 边来源行（无阴影）+ 底部唯一主行动；主色只给编号/主按钮/等级选中 | practice_setup_screen | ☐ |
| O2 | §四A | 答题页：顶部题号 + 等级标签 + 3px 进度线 + 题型/来源行 + 纸面题干/选项 + 作答纸卡（112px）+ **底部唯一主行动**（提交批改）+ 本题来源行 | practice_flow_screen | ☐ |
| O3 | §六-3 | 批改结果页：得分环 + 档位重音、维度条统一、错误条降噪（去掉脏红/withAlpha 杂色）；低干扰 | practice_result_view | ☐ |
| O4 | IMPLEMENT 2.4-4 | 写译工作台 / 题库 / 练习中心 / 旧计划页统一 A 纸面（可复用局部纸面件，不新造组件体系） | writing/**、output/** | ☐ |
| O5 | IMPLEMENT 2.4-4 | 输出首页 / 练习中心**入口**借 B 果冻头图（渐变+光斑+白胶囊 CTA）；内页保持 A（炫技在入口、专注在内页） | output_home / practice 入口 | ☐ |
| O6 | §四A 组件 / D3 | 4 个局部件：`V4LevelTabs`（细边扁平胶囊）/`V4PaperRow`/`V4SourceLine`/`V4IndexHead` 存在且被真实引用（或 Lead 批准的替代方案并记录） | v4_kit 或局部文件 | ☐ |

### 4.2 P0-1 来源（哪年哪套）

| ID | 设计出处 | 必须实现项（可验证判据） | 生产文件 | 状态 |
|---|---|---|---|---|
| O7 | §一 S1 | 入口补**年份/套数**选择（不限/2024/2023/2022/2021 + 第 1/2/3 套可空）→ `composeFromExam(year:)` 真传（不再恒 null） | practice_setup 弹层 | ☐ |
| O8 | §一 S2 | 纯函数 `parsePaperMeta({url, hitTitle, pageText})`：正则 `(20\d{2})\s*[年./-]\s*(\d{1,2})\s*月` + `第\s*([一二三四五六七八九十\d]+)\s*套` + `\bset\s*([1-9])\b`；**只认命中不猜**（年+月才写月，套号命中才写套），都没命中返回空 + siteHost；**单测覆盖命中/不命中** | output_composer 工具区 | ☐ |
| O9 | §一 S3 | `OutputSetSpec` 加 `int? paperYear` / `String paperLabel` / `String sourceSite`；`composeFromExam` 填入；title 改 `'英语四级(CET-4) · 2023 年 12 月第 1 套 · 写作真题'`（无年份退化为「近年」） | output_composer | ☐ |
| O10 | §一 S4 | `_saveSet` 真写 `paper_year`/`paper_label`（去掉 `paper_label: ''` 硬编码）；`source` 保持 exam；**0 迁移**（列已存在 database:394-395） | practice_setup | ☐ |
| O11 | §一 S5 | 展示统一一行「等级 · 年份套数 · 来源站点 · 校对」：①题库卡 ②答题页（把「真题来源·已标注」升级为可解析来源行）③历史重练还原补 `paper*/licenseNote/sourceUrls`（现在还原只带 title/examType/section/rubric/tasks） | practice_history / practice_flow | ☐ |
| O12 | §一 风险 | 不许擅自给 `exercise_items` 加 `source_url` 列（需先给 Lead 方案获批）；模型侧继续**禁止**编造年份标签 | git diff database.dart + 提示词核对 | ☐ |

### 4.3 P0-2 四六级分桶/拆目标

| ID | 设计出处 | 必须实现项（可验证判据） | 生产文件 | 状态 |
|---|---|---|---|---|
| O13 | §2.3 P1 | 设置页 + 题库页加等级筛选行「全部/CET-4/CET-6/考研/雅思」；题库 `_load()` 真传 `examType`（`listExerciseSets(examType:)` 现成 database:2577-2580）；新建时当前筛选值写进 `exam_type`；卡片 meta 显示等级短名 | practice_history / practice_setup | ☑（含 P2-1 修复：`resolveExamType` 让材料出题也吃筛选 override，output_composer:896/973/982 + practice_setup:329 + 3 单测） |
| O14 | §2.3 P1.5 | `examTypeFromGoalIds` 内部改用 `targetExamOf`（中文「四六级」也能映射，不再落 `none`）；真题链路不再一律 `cet4`；单测覆盖中文标签映射 | output_composer + output_source | ☐ |
| O15 | §2.3 P1.5 | 老数据回填按钮（设置页显式操作）：仅对 `source='exam'` 且 `paper_label` 空；title/URL 命中 `四级|CET-4`→cet4、`六级|CET-6`→cet6、四六级/无标记→保持 none 标"待定级"；**不隐式迁移、UUID 不动、只 UPDATE 两列** | 设置页 + database 调用 | ☐ |
| O16 | §2.3 P2 | 拆「四级」「六级」两个学习目标：`DrillCatalog.goals` 增 cet4/cet6（保留「四六级」通用）；`LearnerModel.goals` 旧「四六级」**兼容迁移**（不自动改写已存数据）；设置页/统计/推荐跟随；单测覆盖旧数据迁移 | drill_catalog + learner_model + 相关 UI | ☐ |
| O17 | §2.3 P2 | 内置词池/作文池按等级切分：词汇改用 `ExamVocab.wordsFor('cet4'/'cet6')`（现成 exam_vocab:130-146）；作文题按 rubric 分池（cet4_writing / 新增 cet6_writing） | output_bank / drill 相关 | ☐ |
| O18 | IMPLEMENT 2.4 验收 | 交付：`docs/OUTPUT-IMPLEMENT.md` 对照表；渲染 **≥8 张** `output-impl-*.png`（输出首页/练习中心/四阶设置/答题/批改/写译工作台/题库含筛选/计划页）；单测（年份抽取/CET 映射/分桶过滤/goals 迁移）；analyze 0/0 | docs/ + test/ | ☐ |

## 5. 上一轮（round1）遗留复验（不许"看着修了其实没修"）

> 对应 task-3（material-fix 已交付）+ 输入内页小 bug（Lead 已修）。逐项复核：代码 + 图。

| ID | 判据 | 证据点 | 状态 |
|---|---|---|---|
| B1 | 频道页发现/我的卡：**有真封面才画图，无图纯文字版式**（不许渐变假封面/「原版书」占位） | `material_channel_screen.dart` `_resultCard`/`_mineCard` + `read_image docs/ui-preview/real/channel-no-cover.png`：实看=纯文字卡（标题/来源类型胶囊/三动作），无渐变假封面；代码 `shelfCoverHasImage` 分支 | ☑ |
| B2 | 书架 3D/网格无真封面时用**标题文字版式**（不再程序化假封面） | 代码：`shelf_carousel_view.dart:405-449` `CoverOrText`、`shelf_cover_grid.dart:258-317`（图挂/首帧→TextCover，永不白块/假封面）；图：`read_image shelf_carousel.png`(11-06 22:07)/`shelf_detail.png` 实看=白卡文字版式（种类+标题+幽灵字+难度胶囊+强调竖条），非渐变封面。**但 docs 里仍留着旧命名 `shelf-carousel.png`(11-05)/`shelf-detail.png`(11-04) 的假封面旧图 → 交付物 P2，见 R1 报告** | ☑（附 P2） |
| B3 | 顶部分类条**随滚动滚走**（不再固定遮挡），收起后仍能看出当前频道范围 | 代码：`CustomScrollView`+`SliverToBoxAdapter(_channelHeaderBar)`（channel 1847-1852 / 2406-2411）；图：`read_image channel-collapsed.png` 实看=chips 已滚走，出现紧凑「按题材 · 整个方向 / 改范围」条 | ☑ |
| B4 | 真分页：发现+我的都每页 10 条、页码控件（上一页/第X/Y页/下一页、首末禁用）、切页回顶、分组保留、继续找更多追加且页数增加 | **已实测**：`bash tool/lockrun.sh test test/material_channel_paging_test.dart test/material_channel_test.dart --no-pub` → **+42 全绿**（paging 7 + channel 35，含「12 条结果分 2 页：第1页10条/第2页2条」渲染用例）；图 `channel-no-cover.png` 底部「第 1 / 1 页 · 共 3 篇 · 每页 10 条」+ 上一页禁用 | ☑ |
| B5 | 输入底部弹层**双拖拽横杠**已消除（6 处自绘 handle 删除，统一系统 handle） | grep `width: 40` 于 analysis_mode_picker/word_detail_sheet/sub_category_input/my_materials_section/api_settings/write_review_screen = **0 命中** | ☑ |
| B6 | 识图「已校验:…」行**自动换行不裁切**、不与下条重叠 | `ai_result_header.dart:158-188`：guardNote 行已改 `Flexible` + Text 自动换行（注释自证 2026-11-06 真机截图） | ☑ |
| B7 | P2 数据层收尾：`setMaterialTitleCn`→bool / `deleteMaterial`<0 / store 返回成败 / 快照上限 120 / `ingestText` url 身份 / 花费文案口径 / 付费刷新确认，**调用方逐处判失败** | 签名：database.dart:4707(bool)/:2752(-1 于 :2777-2780)；store: material_channel.dart:252/336/341/364/369 全 bool。调用方：channel:1322-1326/1373-1377/935-947/1152-1159/1342-1351 全判 ✓；material_library:172-176/213-217/255-256/484-487 全判 ✓。**遗留 2 处 P3**：`bookshelf_screen.dart:207` 忽略 bool（后台补译名，无假成功提示，影响低）；`legacy_material_center_screen.dart:526/552` 忽略 bool（旧页疑似已不可达，见下）。`_saveToMine` 里 `removeHiddenMaterial` 循环忽略返回值（:1161-1163，写失败时"已保存"可能重载后仍被隐藏，P3）。花费口径已如实：:2038「官方搜索约 X 元(模型未计)」/ :1480 弹窗「模型调用另计」✓；达上限刷新已改为「替换」清空重搜（:1448-1504 `_refreshAtCap`）✓；QA-N1 子分类绑定已改方向级 key（:486-491 `_mineStoreId`/`_mineStoreKeys`）✓ | ◐（P3 ×3） |
| B8 | URL 归一唯一实现：`url_key.dart` 被 channel/discovery 引用，旧两份实现删除（不许留第二份） | 定义只有 `url_key.dart:18`；`material_discovery.dart:662` 的 `dedupeKeyOf` 是**一行别名** `=> normalizedUrlKey(url)`（保留旧名兼容调用方/测试，非第二份实现）；channel 顶部 re-export | ☑ |
| B9 | **P2-8**：频道页「去设置需求」不再进旧 300 条页 —— `MaterialBrowseScreen` 加 `settingsOnly` 模式（只显示需求编辑器 + 保存，保存后 `pop(true)`），频道页接线由 find 做；点进入后**不应出现历史材料列表**，保存返回后频道页应刷新 | 代码：`material_browse_screen.dart:31/37` 参数、`:67-71` settingsOnly 时**不读 shelf(300)**、`:112-125` 保存后 `pop(true)`、`:152-166` 标题「设置需求」/走 `_settingsBody` 无结果列表；频道页 `_openNeedSettings` push<bool>(settingsOnly:true) 后 `_refreshPrefsAndNeed + _reloadAll + saved==true 提示`（channel:1422-1436） | ☑（代码级；点验待真机/渲染） |

## 6. QA 复核动作（我每主题固定做，交付时附）

1. **读 diff**：`git status --short` + 逐文件 `git diff`，对照 §1.1 作用域表 → 越界即 P0；顺带查 G2（TODO/占位）与 G8（pubspec/dbVersion）。
2. **对照表抽验**：每主题随机抽 ≥8 条设计项，按 file:line 回读代码确认判据（数值/文案/结构），不是看文档写了就算。
3. **接线抽验**：每主题 ≥5 个按钮/入口，从 onTap 追到真实调用（store/DB/discover），确认不是 `() {}` 或只弹 SnackBar。
4. **渲染逐张**：`read_image` 每张 PNG，对照设计判据（配色/字阶/结构/有无假数据），并核对张数与命名清单。
5. **测试/analyze**：`bash tool/lockrun.sh test <该主题 test> --no-pub` + `bash tool/lockrun.sh analyze --no-pub lib`；记录 passed/failed 与 0/0；与旧基线对比无回归。跑前确认无并发 flutter。
6. **写报告**：`docs/QA-IMPLEMENT-<主题>.md`：逐项 ☑/✗ + 证据 file:line/图 + P0 退回清单（每条写"要求补什么、改哪个文件"）+ 该主题通过/不通过结论。

## 7. 交付物命名清单（缺一即 P0）

| 主题 | 对照表 | 渲染图（docs/ui-preview/real/） | 测试 |
|---|---|---|---|
| 阅读器 | READER-C-IMPLEMENT.md | reader-c-*.png ≥8（首屏/控制台/纸白/米黄/墨夜/目录/设置/查词/翻译进行中） | test/reader_c_*（≥4 交互用例）+ 旧 reader 测试回归 |
| 找材料 | FIND-MATERIAL-IMPLEMENT.md | find-material-impl-*.png ≥7（入口/自由搜空态/自由搜结果/按需依据面板/按需结果/无封面卡/空态） | test/find_material_* + material_result_list_test + 频道页回归 |
| 助理我的 | ASSISTANT-MINE-IMPLEMENT.md | assist-mine-impl-*.png ≥12（助理首页/任务详情/复盘/我的首页/统计/周报/错误档案/学习偏好/API设置/写译记录/备份/关于） | test/tutor_* + test/profile_*（TutorBriefing+空态）+ 现有无回归 |
| 输出 | OUTPUT-IMPLEMENT.md | output-impl-*.png ≥8（输出首页/练习中心/四阶设置/答题/批改/写译工作台/题库含筛选/计划页） | test/output_* + 年份抽取/CET 映射/分桶/迁移单测 |
| 最终 | — | 四主题全部图 + 旧图复验（channel-*/shelf-*/reader-plan-*） | `bash tool/final_gate.sh`（若存在）全绿 |

> 本清单是验收基准：实现 agent 交付后由 Lead 转我或我从 task 板看到完成 → 我按 §6 逐项复核，写 `docs/QA-IMPLEMENT-<主题>.md`，缺项记 P0 退回。
