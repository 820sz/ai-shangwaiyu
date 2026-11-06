# 阅读器 C 方案实施对照表（2026-11-06 用户拍板：C 版面 + B 的纸张三色 + 真实进度%）

> 本文件是**交付对照表**：设计条目 → 生产实现 `file:line` → 真实渲染图。
> 设计来源：`docs/READER-REDESIGN-OPTIONS-2026-11-06.md` §1/§3/§4/§7；
> 验收口径：`docs/IMPLEMENT-PLAN-2026-11-06.md` §0/§2.1。
>
> 所有渲染图由 **生产组件**跑出来的（不是设计稿重画）：
> `test/reader_c_render_test.dart` 用 sqflite_common_ffi 起真库种一篇外刊 +
> 真 Hive 设置，直接 pump 生产页 `MaterialReaderScreen`（390×844 @3x），
> 控制台/目录/设置/续读/查词都是从真实交互点进去的。
> 图在 `docs/ui-preview/real/reader-c-*.png`（同时备份到 `build/ui_real/`）。

---

## 0. 一句话结论

C 的「零常驻按钮 + 一张纸 + 常驻进度」全部落到生产代码，B 的「纸张三色」搬进
阅读设置并持久化，进度 % 从"按 2500 词一块粗估"改成真实滚动比例 + 只重建进度组件。
本主题**没有**动全局主题 / 其它屏幕 / 数据库结构 / pubspec / dbVersion。

---

## 1. 设计条目 → 实现 → 渲染图（逐项）

### 1.1 配色与纸张（§4 配色 + §3 B 的纸张色卡）

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 冷灰纸底 `#EEEFEA`（C 基底） | `lib/widgets/reader_paper.dart:85` `paletteOf(ReaderPaper.white)` | `reader-c-first-white.png`、`reader-c-paper-white.png` |
| 弹层底 `#F8F8F4` | 同上（`sheet`） | `reader-c-console.png`、`reader-c-settings.png` |
| 近黑 `#15181A` / 次要 `#494F51` / 极淡 `#8C918F` 三档文字色 | 同上（`ink` / `inkSoft` / `inkFaint`），正文/署名/栏目标签分别取用 | 全部图 |
| 唯一强调砖红 `#B23A2C` | 同上（`accent`）；生词下划线/进度/选中态/主按钮只此一色 | 全部图（重点 `reader-c-first-white.png` 生词、`reader-c-paper-white.png` 竖轨） |
| 线 `#D7D9D2` | 同上（`hairline`） | 刊头双线、行边框、轨道底 |
| 三张纸：纸白 / 米黄 / 墨夜 | `lib/services/reader_settings.dart:187` `ReaderPaper` + `reader_paper.dart:85` 三套色值 | `reader-c-paper-white/beige/night.png` |
| 墨夜纸砖红提亮（可读性） | `reader_paper.dart:120` `#E0604F`（原色在深纸上仅 2.9:1，必须提亮；同色相） | `reader-c-paper-night.png` |
| 阅读器局部换肤、不动全局主题 | `reader_paper.dart:190` `readerTheme()`；页面用 `Theme(data: readerTheme(...))` 只包阅读器子树（`material_reader_screen.dart:2116`），共享弹层也跟着纸色走 | 全部图 |

### 1.2 字阶（§4 6 档）

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 标题 28 / 1.1 / w900 / -0.8 | `reader_paper.dart:140` `ReaderType.title/titleHeight/titleSpacing`；用在 `material_reader_screen.dart:1126` `_readingLead` | `reader-c-first-white.png` |
| 栏目标签 9.5 / 1.3 / +1.6 | `ReaderType.kicker`；`_readingLead` 顶部 `READING · 文章` | `reader-c-first-white.png` |
| 署名 10.5 / 1.4 / +0.3 | `ReaderType.signature`；`_readingLead` 第二行（作者 · CEFR · 分钟 · 已知词比） | `reader-c-first-white.png` |
| 首段 20 / 1.82（导语） | `ReaderType.lead/leadHeight`；`material_reader_screen.dart:2528` `_buildUnit` 的 `isLead` 分支 | `reader-c-first-white.png`（首段比其余大） |
| 其余正文 18 / 1.8（× 用户字号/行距档） | `ReaderSettings.cBodyFontSize()/cBodyLineHeight()`（`reader_settings.dart:126/132`）+ `_buildUnit` 的 bodyStyle | 全部正文图 |
| 译文 13.5 / 1.8 | `ReaderType.translation/translationHeight`；`material_reader_screen.dart:2297` `_buildTranslationArea` | 设置里的预览卡、译文态（见 §5 说明） |
| 生词：墨色词 + 砖红实线下划线（不是满屏链接） | `lib/widgets/reader_text.dart:61` `highlightWords`；`material_reader_screen.dart:2514` `_highlightWords`（来自材料 `top_new_words` 分析） | `reader-c-first-white.png`（只有 generalist / multitasking / distracted / remedy / unglamorous 带线） |
| 刊头 2px + 1px 双线 | `_readingLead` 里 `Container(height:2, color: ink)` + 2 + `Container(height:1, color: hairline)`（`material_reader_screen.dart:1126`） | `reader-c-first-white.png` |
| 首段之后最大行宽（左右 26 / 右侧 46 给进度让位） | `_buildReaderBody` 列表 `padding: EdgeInsets.fromLTRB(26, 8, 46, 30)`（`material_reader_screen.dart:2193`） | 全部正文图 |

### 1.3 零常驻按钮 + 底部把手区（§4 零常驻按钮）

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 底部 2px 贴底进度线 | `lib/widgets/reader_progress.dart:109` `ReaderProgressLine`；由 `ReaderBottomDock` 渲染 | 全部正文图底部 |
| 42px 把手区：左 `%` / 中 36×4 抓手 / 右「上滑工具」 | `lib/widgets/reader_action_bar.dart:21` `ReaderBottomDock`（`handleHeight = 42`、handle 36×4） | 全部正文图底部 |
| 没有任何图标按钮 / FAB / 动作栏 | 旧 `ReaderActionBar` 已整体替换；页面不再有 `AppBar`/`FloatingActionButton`（`material_reader_screen.dart:2116` 起） | 全部图；测试 `reader_c_widget_test.dart`「底部零常驻按钮」断言把手区无任何按钮控件 |
| 上滑/点击把手打开控制台 | `ReaderBottomDock` 的 `onVerticalDragEnd`（阈值 16px/fling 220）+ `onOpenConsole` | `reader-c-console.png` |
| 返回不压正文（顶部安全层） | `material_reader_screen.dart:2265` `_readerTopBar`：44px 纸色顶条，正文从顶条下沿开始滚 | `reader-c-first-white.png`（刊头完整）、`reader-c-paper-white.png`（正文滚到中间也不被压） |

### 1.4 右侧进度（§4 进度）

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 右侧悬浮 `%` 胶囊（10.5/w800，纸底 0.92 + 边框） | `lib/widgets/reader_progress.dart:20` `ReaderProgressRail` | `reader-c-paper-white.png`（37%） |
| 96px 竖轨道（3px 宽，砖红按比例填充） | 同上（`railHeight = 96`、`railWidth = 3`） | `reader-c-paper-white/beige/night.png` |
| 正文右侧内边距 46 让位 | `_buildReaderBody` 列表 padding 右 46 | 全部正文图 |
| 点胶囊也能打开控制台 | `ReaderProgressRail.onTap` → `_openConsole` | — |

### 1.5 上滑「阅读控制台」4 组（§4 弹层）

组件：`lib/widgets/reader_console.dart:99` `ReaderConsoleSheet`；数据快照
`material_reader_screen.dart:828` `_consoleData()`；入口 `material_reader_screen.dart:816` `_openConsole()`。

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 组 1 进度卡：已读 + 「第 N 段 / 共 M 段」+ 34px 数字 + 继续阅读 + 3px 进度线 | `reader_console.dart:250` `_progressGroup` | `reader-c-console.png` |
| 组 2 学习：翻译 / 追问 / 收词 三块等宽方块 | `reader_console.dart:174` 起（`ReaderSheetTile`） | `reader-c-console.png` |
| 学习组补充「收词存到 … 改」 | `reader_console.dart:216`（保存位置会随材料带出，改保存位置能力保留） | `reader-c-console-material.png` |
| 组 3 目录：3 行紧凑行（序号 + 节名 + 本节 %） | `reader_console.dart:346` `_tocRows`（多于 3 节时给「全部 N 节」入口，**设计外增项**，见 §6） | `reader-c-console.png`、`reader-c-console-material.png` |
| 组 4 材料：字号与行距 / 模型与思考档 / 导出·听写·读完 | `reader_console.dart:230` 起（`ReaderSheetRow`） | `reader-c-console-material.png`（滚到底完整可见） |
| 组 4 补充「丰富形式」行（**设计外增项**，保留 v2.9 能力） | `reader_console.dart:236` 起 | `reader-c-console-material.png` |

### 1.6 弹层全部按 C 重排（§4 与 plan §2.1-8）

统一外壳：`lib/widgets/reader_sheets.dart:22` `ReaderSheetSurface`（纸色 + 22px 顶部圆角 +
36×4 抓手 + 栏目标签语言 + 自带 `readerTheme`，**弹层内也吃当前纸张色**）。

| 设计条目 | 实现 | 渲染图 |
|---|---|---|
| 阅读设置 = 字号 5 档 / 行距 3 档 / **纸张三色卡 + 实时预览卡** | `reader_sheets.dart:331` `ReaderSettingsSheet`；页面 `material_reader_screen.dart:1213` `_showReaderSettings`（改完立刻生效 + `ReaderSettings.setPaper/setFontScale/setLineHeight` 落 Hive） | `reader-c-settings.png`、`reader-c-settings-night.png` |
| 目录弹层（每节 %，不是"大字裸列表"） | `reader_sheets.dart:848` `ReaderTocSheet`；页面 `_showToc`（`material_reader_screen.dart:1374`） | `reader-c-toc.png` |
| 模型与思考档 | `reader_sheets.dart:609` `ReaderModelSheet`；页面 `_showModelSheet` | 控制台材料组入口 |
| 材料动作（导出/听写/读完/原文链接） | `reader_sheets.dart:761` `ReaderActionSheet`；页面 `_showMaterialActions`（`material_reader_screen.dart:774`） | 控制台材料组入口 |
| 续读「继续 / 从头」 | `reader_sheets.dart:916` `ReaderResumeSheet`；页面 `_askResume` 按 **percent** 跳（`material_reader_screen.dart:1426/1460`） | `reader-c-resume.png` |
| 收词确认 | `reader_sheets.dart:1035` `ReaderPickedSheet` | 控制台学习组入口 |
| 翻译进度不再压正文（收进弹层 + 顶部 2px 细条） | 旧 `_buildTranslationTray`（93px 实底灰带）已删除；`reader_sheets.dart:1128` `ReaderTranslationSheet` + 页面 `_showTranslationSheet`；顶部细条 `material_reader_screen.dart:2193` 的 `_translationHintLine` | `reader-c-translating.png` |
| 查词弹层 | **共享件** `lib/widgets/word_action_sheet.dart`（不在本主题写作用域，未重排布局）；通过页面 `Theme(readerTheme)` 自动吃 C 纸色；另加了一个**默认 null 的预览注入口** `previewWordInfo`（`word_action_sheet.dart:93`，生产行为零变化）用于渲染图 | `reader-c-word.png`（正常词条结果：词性/释义/英美音标/例句 + 询问 AI/收藏进单词本） |

### 1.7 真实阅读进度 %（§7 五个 Step，plan §2.1-7）

| 设计要求 | 实现 |
|---|---|
| Step 1 `ValueNotifier` 只重建进度组件，不 setState 整屏 | `material_reader_screen.dart:139` 附近字段 `_readingPercent`（`ValueNotifier<double>`）；消费方只有 `ReaderBottomDock` / `ReaderProgressRail` / 控制台进度卡 |
| Step 2 `_onScroll` 更新 | `material_reader_screen.dart:1268` `_onScroll`（写 `_lastScrollRatio` + `_readingPercent`，**没有** `setState`） |
| Step 3 常驻显示 | 右侧胶囊/竖轨（`reader_progress.dart:20`）+ 贴底 2px 线 + 控制台数字 |
| Step 4 落库 percent 真实比例，未读完 ≤99、读完才 100 | `material_reader_screen.dart:1304` `_persist`：`finished ? 100 : (_lastScrollRatio*100).clamp(0,99)`；`_finishReading` 置 1.0（`material_reader_screen.dart:1643`） |
| Step 5 续读按 percent 跳 | `material_reader_screen.dart:1460` `_scrollToPercent`（`jumpTo(maxScrollExtent * percent/100)`） |
| 同一份真值被书架/材料中心读到 | 仍走 `material_progress.percent`（未改表/未加字段），书架 `database.dart:2916`、材料中心 `database.dart:4651` 读同一列 |
| 打开时进度初始化竞态（本轮实测修复） | `material_reader_screen.dart:1490` 附近：初始化必须在 `setState` 后**立刻**执行，否则会晚于滚动监听把用户刚滚出的进度覆盖回 0 |

---

## 2. 纸张三色规格与可读性（机器守门）

色值（`lib/widgets/reader_paper.dart:85`）：

| 令牌 | 纸白（默认，C 基底） | 米黄（B 的暖纸） | 墨夜（深色纸） |
|---|---|---|---|
| `page` | `#EEEFEA` | `#F4EFE3` | `#16181C` |
| `sheet` | `#F8F8F4` | `#FBF7ED` | `#1E2126` |
| `ink` | `#15181A` | `#241F17` | `#ECEDE8` |
| `inkSoft`（译文） | `#494F51` | `#6E6555` | `#B6BAB4` |
| `inkFaint` | `#8C918F` | `#9A9080` | `#8F9691` |
| `hairline` | `#D7D9D2` | `#E2D8C4` | `#2E3238` |
| `accent`（唯一强调） | `#B23A2C` | `#B23A2C` | `#E0604F`（提亮版：原色在深纸上仅 2.9:1） |
| `transBg`（译文底） | `#ECEDE6` | `#F0E9DA` | `#23262C` |
| `selectedBg`（选中态） | `#E4E0D7` | `#E9DFCB` | `#23262B` |

对比度机器守门：`test/reader_c_paper_test.dart`（WCAG `contrastRatio()` 在
`reader_paper.dart:257`）——三张纸逐项断言：正文 > 7:1、译文次要色 ≥ 4.5:1、
砖红强调 ≥ 4.5:1、砖红在译文底/选中底上 ≥ 4:1、主按钮字色 ≥ 7:1，
外加「墨夜砖红必须提亮」一条（原色 < 3:1）。

持久化：`ReaderSettings.keyReaderPaper = 'reader_paper'`（settings Hive box，
`reader_settings.dart:153`），存枚举名；兼容手改成 `0/1/2`；脏数据回默认纸白。
切换在 `_showReaderSettings.onChanged` 里**立刻** `setState` + 落库，页面/弹层同帧换纸；
重启读回由 `initState`（`material_reader_screen.dart:296` 附近）完成。

---

## 3. 渲染图清单（13 张，全部 390×844 @3x = 1170×2532）

| # | 文件 | 屏 | 生成方式 |
|---|---|---|---|
| 1 | `docs/ui-preview/real/reader-c-first-white.png` | 首屏：刊头双线 / 首段 20 / 顶部安全条 / 底部零按钮 | 真实页（0%） |
| 2 | `reader-c-paper-white.png` | 纸白 · 阅读中（右侧 37% 胶囊 + 96px 竖轨） | 真实页 + 真实滚动到 37% |
| 3 | `reader-c-paper-beige.png` | 米黄 · 同上 | 真实页（Hive 切纸） |
| 4 | `reader-c-paper-night.png` | 墨夜 · 同上 | 真实页（Hive 切纸） |
| 5 | `reader-c-console.png` | 上滑阅读控制台（4 组顶部） | 真实页 + 点底部「上滑工具」 |
| 6 | `reader-c-console-material.png` | 控制台滚到底：材料组完整可见（不被裁） | 真实页 + 控制台内滚动 |
| 7 | `reader-c-settings.png` | 阅读设置：字号/行距/三色卡/实时预览 | 控制台 →「字号与行距」 |
| 8 | `reader-c-settings-night.png` | 墨夜纸上的设置（弹层跟着换纸） | 同上，纸=墨夜 |
| 9 | `reader-c-toc.png` | 完整目录（每节 %、当前节砖红） | 控制台 →「全部 6 节」 |
| 10 | `reader-c-resume.png` | 续读弹层（上次 37%） | 真库预置 37% 进度后打开 |
| 11 | `reader-c-translating.png` | 翻译进行中（生产弹层 + 真实 ProgressStageBar） | 生产组件 + 假进度数据 |
| 12 | `reader-c-console-night.png` | 墨夜纸上的控制台 | 真实页 + 控制台 |
| 13 | `reader-c-word.png` | 查词弹层（共享件 + C 纸色主题） | 生产共享件 + 零配置降级态 |

---

## 4. 测试与静态检查

| 命令 | 结果 |
|---|---|
| `bash tool/lockrun.sh test test/reader_c_widget_test.dart --no-pub` | **5/5 通过**（底部零按钮 / 控制台上滑 4 组 / 控制台滚到底进设置 / 纸色切换持久化 + 重开保留 / 进度%真值 37%） |
| `bash tool/lockrun.sh test test/reader_c_paper_test.dart --no-pub` | **8/8 通过**（C 6 档字阶 / 三纸对比度逐项 / 墨夜提亮 / 纸张持久化往返 + 脏数据） |
| `bash tool/lockrun.sh test test/reader_c_render_test.dart --no-pub` | **14/14 通过**（出 13 张真图；含「落库 percent ≤99」断言 + 翻译屏主题探针：共享组件 `LinearProgressIndicator` 必须解析到砖红主色，防共享件漏出全局果冻蓝） |
| `bash tool/lockrun.sh test test/reader_settings_test.dart test/reader_text_test.dart test/reader_units_test.dart --no-pub --concurrency=1` | **29/29 通过**（阅读设置/选词/切段旧逻辑回归，EXIT=0） |
| `bash tool/lockrun.sh analyze --no-pub lib/screens/input lib/widgets` | **本主题 8 个文件 0 error / 0 warning / 0 info**；目录里剩 6 条**存量 info** 全在别人的文件（`process_chat.dart` ×5、`ai_article_section.dart` ×1），按 plan §0.4「存量 info 不算」 |

专项测试覆盖的验收点：
- **底部零常驻按钮**：断言 `ReaderBottomDock` 内无 `IconButton/FilledButton/TextButton/OutlinedButton/ElevatedButton/FloatingActionButton`，全页无 `FloatingActionButton`；
- **控制台上滑**：真实手势上滑 36×4 抓手 → 4 组标题（阅读控制台/学习/目录/材料）+ 继续阅读 + 字号与行距 都在；
- **纸色持久化**：点「米黄」→ 页面 Scaffold 底色立刻变 `#F4EFE3` → Hive `reader_paper='beige'` → 重开页面仍米黄；
- **进度更新**：真实滚动到 37% → 右侧胶囊/贴底数字都是 `37%`（只重建 ValueListenable 组件，`_onScroll` 无 `setState`）；
- **落库真值**：滚到末尾 → `material_progress.percent` 在 (90,99]，未点「读完了」永远不写 100。

---

## 5. 保留功能回归（C 改造没有拆掉的现有能力）

| 功能 | 现在的位置（C 方案下） |
|---|---|
| 逐段翻译（随读随翻 / 继续翻后文 / 整章 / 重试失败段 / 取消） | 控制台「学习 → 翻译」→ 翻译弹层（`ReaderTranslationSheet`）；正文逐段译文样式见 `_buildTranslationArea` |
| 保存位置（分类 / 材料名 / 页码） | 控制台学习组「收词存到 … 改」→ `_changeSaveTarget`；收词弹层里也能改 |
| 进度落盘 + 会话统计 | `_persist` 未改落库时机/节流，只换 percent 口径 |
| 书架 / 收藏 | 控制台标题行书架开关（`reader_console.dart:135`）；退出时仍问「放进书架 / 收藏夹 / 就看看」`_askShelfOnExit` |
| 追问（整篇 / 单段） | 控制台「学习 → 追问」；点译文仍可追问这一段 |
| 阅读设置 | 控制台「材料 → 字号与行距」（C 版含纸张三色） |
| 目录 | 控制台「目录」3 行 +「全部 N 节」完整目录弹层 |
| 丰富形式 | 控制台「材料 → 丰富形式」 |
| 长按选词 / 点词查词 / 生词高亮 | `TappablePassage`（新增 `highlightWords`，只有生词画线）；点词→词动作弹层→收词/追问 |
| 图片 / 原文链接 / 听写 / 导出 / 读完 | 控制台「材料 → 导出 / 听写 / 读完」动作弹层 + 原文链接行 |
| PDF 兜底 / 音频条 / AI 内容块 | 未改（音频 `AudioPlayerBar` 仍在正文上方；`MaterialBlockView` 仍插在块末；PDF 走原 `material_content` 路径） |

---

## 5.1 旧功能回归结论（逐项）

| 旧功能 | 回归方式 | 结论 |
|---|---|---|
| 翻译范围 / 随读随翻 / 继续翻后文 / 整章 / 重试 / 取消 | 代码路径保留 + 控制台/翻译弹层真实渲染（`reader-c-translating.png`）+ `reader_units`/`reader_text` 单测 | ✅ 未丢；真 API 调用无法在测试环境实跑（需 Key） |
| 保存位置（分类/材料名/页码） | 控制台学习组「收词存到…改」→ `_changeSaveTarget`（复用 category_picker/sub_category_input） | ✅ 入口保留 |
| 进度落盘 + 会话统计 | 真实页滚动 → 真库读 `material_progress.percent`（`reader_c_render_test` 断言 (90,99]） | ✅ 已由旧「0/100 粗估」修为真实比例 |
| 书架 / 收藏 | 控制台标题行书架开关 + 退出三选一 `_askShelfOnExit` | ✅ 入口保留；书架读同一 percent 列 |
| 追问（整篇/单段） | 控制台学习组「追问」+ 点译文追问（`_openFollowUp`/`_askAboutChunk`） | ✅ |
| 阅读设置 | 控制台材料组「字号与行距」→ C 版设置（含纸张三色） | ✅ 5 档字号 / 3 档行距 / 3 纸全部生效 + 持久化（widget test） |
| 目录（全部章节） | 控制台目录 3 行 + 「全部 N 节」→ 完整目录弹层（`reader-c-toc.png`）；跳转 `_scrollToChunk` | ✅ |
| 丰富形式 | 控制台材料组「丰富形式」→ 原 `_RichFormsSheet`/`MaterialBlockView` | ✅ |
| 长按选词 / 点词 / 生词高亮 | `TappablePassage`（新增 `highlightWords` 只标真生词）+ 词动作弹层（`reader-c-word.png`） | ✅ |
| 图片 / 原文链接 / 听写 / 导出 / 读完 | 材料动作弹层 + 原文链接行；图片/音频条/PDF 兜底代码未改 | ✅ 未改（渲染测试只覆盖文字材料） |
| 续读 | 真实页预置 37% 进度 → 续读弹层（`reader-c-resume.png`）+ `_scrollToPercent` | ✅ |

## 6. 设计外增项（保留能力所需，已写明不隐藏在代码里）

1. **控制台目录组多一行「全部 N 节 · 完整目录」**：设计只写 3 行紧凑行，
   但目录必须能跳全部章节（旧功能），所以 3 行之后给一个入口打开完整目录弹层。
2. **控制台材料组多一行「丰富形式」**：设计 材料组只列 3 行（字号/模型/导出），
   v2.9 的「丰富形式（表格/导图/时间线…）」不能丢，因此加一行（与「原文链接」一起
   归到「导出·听写·读完」动作弹层里的只有原文链接）。
3 **顶部 44px 纸色安全条**：C 设计稿是「悬浮返回圆钮」，实测任何滚动位置都会压字
   （用户截图里第一行被圆钮盖住），改成固定纸色顶条给正文让位 —— 视觉上仍是"纸上
   一颗圆钮"，但零遮挡。
4. **墨夜纸的砖红提亮为 `#E0604F`**：`#B23A2C` 在 `#16181C` 上只有 2.9:1，小字不可读；
   同色相提亮到 4.5:1 以上（测试机器守门）。
5. **字号档位映射**：C 用「18 / 19.5 / 21 / 22.5 / 24 号」5 档（默认 18），
   旧 `[0.85, 1.0, 1.15, 1.3, 1.5]` 与 16 基准**原样保留**在 `ReaderSettings` 里，
   输出板块文章阅读器零影响；C 阅读器按"档位下标 → C 号数"映射。

---

## 7. 未做 / 风险（明确说明，不含糊）

1. **查词弹层布局没有按 C 重排**：它属于共享件 `lib/widgets/word_action_sheet.dart`
   （拍照识图页/另外两个阅读器也在用），不在本主题写作用域。已做的是让它跟随
   `readerTheme` 吃 C 纸色/砖红（`reader-c-word.png` 可见）；如果要连布局一起 C 化，
   需要 Lead 授权改共享件（会影响拍照页）。
   **作用域例外（已获 Lead 批准，2026-11-07）**：见 §7.2。
2. **`reader-c-word.png` 用假词条预览**：测试环境无法连真 API（flutter_test 会
   拦截所有 HttpClient），所以用上述默认 null 注入口喂一条假词条（词性/释义/
   英美音标/例句），弹层其余（词头/保存位置/两个动作）全是生产组件真实渲染。
3. **长书（多块懒加载）的 percent 线性近似**：`maxScrollExtent` 在"后面还没加载"时偏小，
   进度会有轻微跳动 —— 与设计文档 §7.3 注明一致，二期可用「已读块 + 块内比例」二次校准。
   一期按"内容比例"展示/落库，已比旧实现（永远 0/100）准确。
4. **翻译进行中图**用生产弹层 + 假进度数据而非真 API（真 API 需要 Key，测试里假装会给出
   "看起来能用其实是假的"图）。
5. 设计稿的「目录 3 行」在只有 ≤3 节时就是全部；多于 3 节时按当前节取窗口 3 行 +
   「全部 N 节」入口（见 §6.1）。

---

## 7.1 未做的渲染覆盖

- **360dp 窄屏**没有单独出图（本轮 390×844 主流直屏）；控制台/设置里的长标签已加
  省略号保护，但窄屏下四组卡片仍建议真机走一遍（二期）。
- **深色系统主题**：C 的「墨夜纸」已经是深色阅读，但深色系统主题下的其他弹层
  （系统键盘、权限弹窗）未单独验证（二期）。

## 7.2 作用域例外记录（已获 Lead 批准）

| 项 | 内容 |
|---|---|
| 文件 | `lib/widgets/word_action_sheet.dart`（共享件，拍照识图页 / 另外两个阅读器也用；本主题写作用域外） |
| 改动 | 新增**默认 `null`** 的参数 `previewWordInfo`（`showWordActionSheet(... , @visibleForTesting Map<String,String>? previewWordInfo)` → `_WordActionSheet`），`_lookup()` 在传值时直接用该词条、跳过 `completeWordInfo` |
| 生产影响 | **零**：默认 `null` 走原网络查询路径；所有生产调用点一行未改 |
| 用途 | 渲染测试给 `reader-c-word.png` 喂一条假词条（词性/释义/英式美式音标/例句/语法），展示"正常查词结果"而不是零配置报错态 |
| 批准 | Lead 2026-11-07 批准，保留现状 |
| 若需回退 | 删除该参数 + `README` 渲染测试里的传参即可，生产行为不变 |

## 8. 本轮渲染自检抓到并修掉的真 bug（不是"预览好看"那类）

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| 1 | 首屏/纸色图里进度永远 0%（滚到 37% 也不动） | `_load()` 里"把已存 percent 摆到常驻进度"的初始化放在一个 `await`（首开写库）之后，晚于滚动监听执行，把用户刚滚出来的进度又覆盖回 0 | 初始化挪到 `setState` 之后立刻执行（`material_reader_screen.dart` `_load`）；widget 测试「进度%真值 37%」守门 |
| 2 | 翻译弹层/查词弹层里出现**果冻蓝进度条 + 蓝色按钮**，还有 tofu 方块 | 两个全局主题在阅读器局部 Theme 里没被覆盖：`textButtonTheme` 把 TextButton 前景写死果冻蓝，`progressIndicatorTheme.color` 把进度条写死果冻蓝；按钮 textStyle 又绕过当前 textTheme 导致中文 tofu | `readerTheme()` 覆写 `textButtonTheme / filledButtonTheme / outlinedButtonTheme / progressIndicatorTheme`（砖红/墨色 + 接当前 textTheme）；渲染测试加主题探针 `expect(Theme.of(bar).primary, palette.accent)` |
| 3 | 返回圆钮压刊头/正文 | C 设计的"悬浮圆钮"在任意滚动位置都会盖字 | `_readerTopBar`：44px 纸色顶条给正文让位（`material_reader_screen.dart:2265`） |
| 4 | 全篇每个词都有砖红下划线（满屏红线 = 没重点） | C 改造初期给所有词都上了 accent 下划线（旧 TappablePassage 行为是"全部主色虚线"） | `TappablePassage.highlightWords`：只有材料分析出的 `top_new_words` 才画砖红实线（`reader_text.dart:61`、`material_reader_screen.dart:2514`） |
| 5 | 墨夜纸选中态上的砖红对比度只有 3.76:1 | 深色选中底 `#2C3037` 太亮 | 选中底改 `#23262B`，`test/reader_c_paper_test.dart` 断言 ≥4:1 |
| 6 | 渲染 fixture 正文里露出字面量 `\n\n` | 测试 fixture 用了 `'\\n\\n'`（转义成反斜杠+n）而不是真实换行 | fixture 改真换行，全部图重出 |
