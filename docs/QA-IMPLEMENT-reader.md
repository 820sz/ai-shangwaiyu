# QA 实施度复核 · 阅读器 C（C 版面 + 纸张三色 + 真实进度%）· 终版 · 2026-11-07 02:3x

> 复核对象：reader-impl 最终版（task-7）。基准：`docs/QA-IMPLEMENT-CHECKLISTS.md` §1 R1–R15 +
> 设计 `READER-REDESIGN-OPTIONS-2026-11-06.md` §3/§4/§7 + `IMPLEMENT-PLAN-2026-11-06.md` §2.1。
> 方法：13 张 PNG **逐张 read_image** → 15 条清单逐项回代码 → 6 个测试文件 lockrun 实跑 →
> 对照表逐条核（含设计外增项/未做项/作用域例外）→ grep 占位/作用域 → analyze 目录级归因。
> **结论：通过（P0 = 0）**；2 条 P3 记录（设计外增项已写明 / 查词布局未重排属已批准例外）。

## 一、实测数字（我实跑，非转抄）

- 测试：6 个文件 lockrun → **56 passed / 0 failed**
  （`reader_c_widget_test` 5 + `reader_c_paper_test` 8 + `reader_c_render_test` 14 + 旧功能 `reader_settings/reader_text/reader_units` 29 = 56，与交付声明一致）。
- 渲染：13 张 `reader-c-*.png` 全部存在，逐张 read_image（见 §三）。
- 对照表：`docs/READER-C-IMPLEMENT.md` 281 行（§1 逐项 file:line、§2 对比度表、§3 13 图清单、
  §4 测试、§5/5.1 旧功能回归、§6 设计外增项 5 条、§7 未做/风险、§7.1 渲染缺口、§7.2 作用域例外、§8 自检抓到的 6 个真 bug）。
- 作用域：`git status lib/config/ lib/widgets/v4/` = 空（全局零改动）；唯一跨作用域
  `lib/widgets/word_action_sheet.dart` = 新增默认 null 的 `@visibleForTesting previewWordInfo`（diff 已核：生产调用点一行未改），与 §7.2/Lead 批准一致。
- 占位/假数据：`grep TODO|FIXME|占位|后续再做` 于 reader 生产文件 = **0**；渲染用假数据仅存在于测试 fixture + 默认 null 注入口（已记录），生产 UI 无写死假数据。

## 二、15 条清单（R1–R15）

| ID | 结论 | 证据（代码 + 图） |
|---|---|---|
| R1 配色/唯一砖红 | ☑ | `reader_paper.dart:85-133`：纸白 `#EEEFEA/#F8F8F4/#15181A/#494F51/#8C918F/#D7D9D2/#B23A2C`；墨夜 `#16181C` + 提亮砖红 `#E0604F`（注释：原色仅 2.9:1）。图：无第二个彩色强调（蓝/绿均无） |
| R2 6 档字阶 | ☑ | `reader_paper.dart:140-182 ReaderType`：title 28/1.1/-0.8、kicker 9.5/1.3/+1.6、signature 10.5/1.4/+0.3、lead 20/1.82、body 18/1.8、translation 13.5/1.8（按用户字号档等比） |
| R3 刊头双线 | ☑ | `material_reader_screen.dart:1199-1201`：2px ink + 2px 空 + 1px hairline；`first-white.png`/`resume.png` 实看双线 |
| R4 零常驻按钮 | ☑ | 页面无 `AppBar`/`FloatingActionButton`/旧动作栏（grep 只剩 `ReaderBottomDock`+`ReaderProgressRail`，:2247/:2261）；`ReaderBottomDock.handleHeight=42`（reader_action_bar:42）、2px 线 + 左%/中 36×4/右「上滑工具」；`reader_c_widget_test` 断言 0 按钮且全页无 FAB |
| R5 右侧进度 | ☑ | `reader_progress.dart:20/36-42`：胶囊 10.5/w800 + `railHeight=96`/`railWidth=3` 砖红填充；图 `paper-white/beige/night` 37% 胶囊 + 竖轨（墨夜用提亮砖红）；列表右侧 padding 46 让位（doc §1.4） |
| R6 控制台 4 组 | ☑ | `reader_console.dart`：进度卡（`:250`，34px 数字+第N/共M段+继续阅读+3px 线）/学习 3 块（`:174`，翻译/追问/收词）/目录（`:346`，3 行+本节%）/材料（`:230`，字号行距/模型思考档/丰富形式/导出听写读完）；图 `console.png` + `console-material.png`（滚到底材料组完整可见、不被裁） |
| R7 弹层 C 重排 | ☑（附例外） | 统一 `ReaderSheetSurface`（纸色+22 圆角+36×4 抓手+自带 readerTheme）；设置(:331)/目录(:848)/模型(:609)/材料动作(:761)/续读(:916)/收词(:1035)/翻译(:1128) 已重排；图 settings/settings-night/toc/resume/translating 逐张核。**查词弹层是共享件，只跟随纸色、布局未重排**——属 §7 已写明 + §7.2 Lead 批准作用域例外，非隐藏缺项 |
| R8 翻译不压正文 | ☑ | 旧 93px `_buildTranslationTray` 已删；进度/动作收进 `ReaderTranslationSheet` + 顶部 2px 提示线；图 `translating.png` 正文区无灰带 |
| R9 纸张三色 | ☑ | 三套色值齐全（§二 R1）；设置内 3 色卡 + **实时预览卡**（正文 18 号 + 译文砖红竖线）；切换立即生效 + `ReaderSettings.setPaper` 落 Hive（`reader_settings.dart:153/173`、页面 :1238），重启读回（:331）；三纸可读性由 `reader_c_paper_test` 8/8 机器守门（对比度 ≥4.5/≥3/墨夜提亮） |
| R10 真实进度% | ☑ | `_readingPercent = ValueNotifier`（:132）；`_onScroll` 只写 `_lastScrollRatio`+notifier、**无 setState**（:1294-1295，clamp 0.99）；消费方仅 `ReaderProgressRail/Line/BottomDock/Console`（ValueListenableBuilder）；`_persist` 落库真实比例（≤99，finished=100，:1343-1347）；续读按 percent 跳（:1460 `_scrollToPercent`）；图 37% + 渲染测试断言落库 (90,99] |
| R11 旧功能回归 | ☑ | 对照表 §5/§5.1 逐项（翻译/保存位置/落盘/书架/收藏/追问/设置/目录/丰富形式/长按选词/生词高亮/图片/PDF）；旧 3 个测试 29/29 通过；§8-1 修了"初始化晚于滚动监听把进度覆盖回 0"的真 bug |
| R12 交付物 | ☑ | 13 张逐屏图（≥8）；`reader_c_widget_test`(5)/`reader_c_paper_test`(8)/`reader_c_render_test`(14) 全过；对照表 281 行 |
| R13 渲染清单 | ☑ | 13 张覆盖：首屏/纸白/米黄/墨夜(37%)/控制台/控制台滚到底/设置/墨夜设置/目录/续读/翻译中/墨夜控制台/查词；三纸同构建同滚动位一致（同屏只有生词砖红下划线）、无 `\n\n` 字面量、无压字 |
| R14 9 条清单对照 | ☑ | IMPLEMENT §2.1 的 9 条 → 对照表 §1.1/1.2/1.3/1.4/1.5/1.6/1.7 逐条有 file:line+图，另有旧功能/设计外增项/未做项 |
| R15 反向约束 | ☑ | 未改全局 `v4_theme`/`AppFont`/`design_tokens`（git status 空）；阅读排印字号只在 ReaderType/ReaderSettings；无玻璃底栏（实心纸/白条）；只动阅读器作用域 + 已批准的 word_action_sheet 例外 |

## 三、13 张图逐张结论

| 图 | 结论 |
|---|---|
| `first-white` | 首屏：44px 纸色顶条（返回圆钮**不压字**）+ READING·文章 + 标题 + 署名「The Atlantic · C1 · 约8分钟 · 已知92%」（**原「930 词」重复已去**）+ 刊头双线 + 首段略大；只有 generalist/multitasking/distracted 生词砖红下划线（**不再是满屏红线**），0% 胶囊/竖轨/底部 2px 线 + 0% 已读/抓手/上滑工具齐 |
| `paper-white`/`beige`/`night` | 三纸同滚动位 37%：纸底/墨色/砖红各自成立；37% 胶囊 + 竖轨按比例填充（墨夜提亮砖红）；底部 2px 线 37% 填充；**三纸只有生词下划线、无字面量 `\n\n`** |
| `console` / `console-material` | 4 组齐；滚到底**材料组 4 行完整可见不被裁**（字号与行距/模型与思考档/丰富形式/导出·听写·读完） |
| `console-night` | 墨夜纸控制台：暗面+提亮砖红+白胶囊「继续阅读」，可读性正常 |
| `settings` / `settings-night` | 5 档字号 / 3 档行距 / 三纸色卡（当前纸砖红描边）/ 实时预览卡（中英对照、译文砖红竖线）；墨夜版弹层随纸换色 |
| `toc` | 6 节完整目录 + 每节「约 N 词 · 本节 %」+ 当前节砖红边框 ✓；**无字面量 `\n\n`** |
| `resume` | 「上次读到 37%」+ 已读 6 分钟 + 继续(第 2 段)主行动 + 从头开始；底页 37% 竖轨一致 |
| `translating` | 逐段翻译弹层：3/8 段 38% + **砖红**进度条（无蓝色遗留、无 tofu）+ 继续翻后文/整章/重试/关闭译文 + 底部「翻译使用 deepseek-chat · 标准」 |
| `word` | 查词弹层正常词条：词头 + 音标 + 词性 + 释义 + 例句 + 语法 + 保存位置 + 询问 AI/收藏进单词本；C 纸色主题、无 tofu（§7.2 已说明假词条仅用于预览，生产走真查询） |

## 四、设计外增项 / 未做项核验（对照表是否写明）

- §6 设计外增项 **5 条全部写明**：目录组「全部 N 节」入口 / 材料组「丰富形式」行 / **44px 纸色安全条**（替代悬浮圆钮解决压字）/ 墨夜砖红提亮 `#E0604F` / 字号 5 档映射（旧 0.85~1.5 与 16 基准保留不动）。
- §7 未做/风险 **5 条**：查词弹层布局未 C 化（共享件，Lead 批准例外）/ word 图用假词条预览 / 长书懒加载 percent 线性近似（二期校准）/ 翻译图用假进度 / 目录 >3 节取窗口 3 行；§7.1 另写 360dp 与深色系统弹层未验（二期）。
- §8 **6 个自检抓到的真 bug** 与我上轮预检发现一一对应并已修：进度被覆盖回 0（初始化时序）、蓝色进度条+tofu（readerTheme 漏覆盖 textButtonTheme/progressIndicatorTheme）、返回压字（44px 顶条）、满屏下划线（highlightWords 只标 top_new_words）、墨夜选中砖红 3.76:1（选中底改深）、`\n\n` fixture 转义 → 真换行。

## 五、P3（记录即可，不阻塞）

1. `reader-c-word.png` 的词条是测试注入（默认 null、生产零影响，§7/§7.2 已写明）；查词弹层布局仍是共享件旧布局（Lead 已批准例外）。若用户后续要求"查词也 C 化"，需授权改共享件。
2. 长书（多块懒加载）percent 为线性近似，可能有轻微跳动（设计 §7.3 已知，二期可用"已读块+块内比例"校准）；360dp 窄屏/深色系统弹窗未单独渲染（§7.1 已声明）。

## 六、最终结论

**阅读器 C：通过（P0 = 0）**。C 版面（冷灰纸/唯一砖红/6 档字阶/刊头双线/零常驻按钮/右侧胶囊+96px 竖轨/控制台 4 组/弹层重排）、B 的纸张三色（色卡+实时预览+即时生效+Hive 持久化+三纸对比度机器守门）、§7 真实进度%（ValueNotifier 只重建进度组件、`_onScroll` 无 setState、落库真实比例 ≤99、续读按 percent）三项全部落地且有三重证据；13 张逐屏图核过（三纸一致、无压字、无蓝遗、无 `\n\n`、控制台不裁、查词正常）。**可进全量闸门与打包**。
