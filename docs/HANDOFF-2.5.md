# 交接文档 · AI上外语 v2.8

> **写于 2026-09-27;最近更新 2026-10-01(v2.8.0)**。这份文档是给「接手的人 / 上下文被压缩后的我」看的:**读完这一份就能零疑问继续干**。
>
> 事实源分工(别重复造):
> | 文档 | 管什么 |
> |---|---|
> | **本文件 `docs/HANDOFF-2.5.md`** | 做到哪、还剩什么、怎么做、踩过什么坑(随进度更新) |
> | `PLAN.md` 顶部「状态」三行 | 版本号 / 阶段的**唯一事实源**,每次发版必须同步 |
> | `docs/TASK-BOARD-2.5.md` | 本轮用户原话、任务分解、用户决策(做事的边界) |
> | `C:\Users\xi283\.dsh\memory\readflow-project.md`<br>`C:\Users\xi283\.dsh\memory\readflow-dev-session.md` | 跨会话记忆(压缩后自动带回),只放指针与铁律,细节指向本文件 |

---

## 0. 30 秒上手

| 项 | 值 |
|---|---|
| 项目 | **AI上外语**(内部代号 readflow)— Flutter 写的英语学习 App,Android,用户自己 + 几个朋友用 |
| 目录 | `D:\readflow` |
| 远端 | https://github.com/820sz/ai-shangwaiyu(**公开**,AGPL-3.0,gh CLI 已登录 `820sz`,默认分支 **master**) |
| 工具链 | Flutter **3.44.7** stable / Dart 3.12.2 |
| 已发布 | **v2.8.0+65 = Release Latest**(2026-10-01;上版 v2.7.0) |
| 本地 HEAD | 见 §2.2 提交地图(与远端 master 的 tree 保持一致) |
| 绿灯 | analyze **0 error / 0 warning**(11 条存量 info);测试 **790 全绿 + 1 skip** |
| 本轮任务 | 用户 10/1 实测 **10 大条**:追加图片闪退 / 中文材料词汇板块 / 询问 AI 过渡 / 复习卡住与单词截断 / 学习助理重做 / 材料中心视觉与检索大升级 / 输出练习扩展 / 追问抽屉配色 / 我的名片 / 收藏夹分类 —— 全部交付 |
| **下一步** | **等用户真机复测**(见 §8);反馈回来后按老规矩:只做他列的事、先问清楚、每批量做完再报 |

> 📌 **v2.8.0 的任务板在 `docs/TASK-BOARD-2026-10-01.md`**;材料中心的**对标调研**在
> `docs/SPEC-material-discovery-2026-10-01.md`(8 款 App 像素级测量 + 图源本机实测 + Lv 公式 +
> 流式检索状态机)。更早:`docs/TASK-BOARD-2026-09-29.md`(6 大条)、
> `docs/TASK-BOARD-2026-09-28.md`(11 条,含识图提示词原文)。

**三条命令**(PowerShell,先 `cd D:\readflow`):
```powershell
$env:FLUTTER_ALREADY_LOCKED = 'true'   # 每个新 shell 都要,否则 flutter 卡锁
flutter analyze --no-fatal-infos       # 期望 0 error / 0 warning(11 条 info 是存量)
flutter test                           # 期望 790 全绿 + 1 skip
```

---

## 1. 用户是谁 · 铁律(违反会被骂)

用户 = xi283,中文,Windows 11,手机真机测(Android)。以下是他明确表达过的,按重要性排:

1. **只做他列的事,不要自作主张加功能**。他列过 10 条,我就只做 10 条;多做的(桌面小组件、诊断页、探针脚本)都被点名过。
2. **不清楚先问,别猜着做**。
3. **做好规划、优先级、边界,并且要有"留存"**(文档化)。
4. **不要完成一小个就停住** —— 一批活要连着做完再报。
5. **但也别把活攒到最后才汇报** —— 每完成一项/一批就报一次进度;他反感长时间静默("一让汇报进度就完成了")。
6. **遇到 UI 问题先信用户、先查渲染层**。历史上我死磕数据层绕了一整晚,而根因就是一行 `TextOverflow.ellipsis`。
7. **发布前必须 bump `pubspec.yaml` 版本号**,构建后 `aapt dump badging` 验证 versionName(曾忘 bump 让用户白装两次)。
8. **禁止任何自杀式操作**:不许 taskkill / Stop-Process / pkill / 杀 node / 动 3080 端口。需要重启服务只能写 `.bat` 放到 `D:\deepseek harness 工作区\` 让用户双击。
9. **不要用 PowerShell 文本管道改源码**(UTF-8 → GBK 会乱码成 mojibake);改文件只用 read / edit / write 工具。
10. **表情包**:气氛合适时主动 `send_meme`(先 search 拿候选,`[表情: 描述]` 里的描述必须抄候选原文);谈正事/干活时克制。

---

## 2. 现在做到哪儿了

### 2.1 版本线(最近)

| 版本 | 内容 | 状态 |
|---|---|---|
| v2.2.0 | 2.0 阶段三:听说与生产力 | 已发 |
| v2.3.0 | 桌面小组件 + 材料中心可用性修复 + 结构整理 | 已发 |
| v2.3.1 | 诊断增强(材料源健康表 + 小组件状态) | 已发 |
| v2.3.2 | 材料库整链路测试挖出 2 个真 bug(入库未读不显示 / 书架 id 恒 0 点不开) | 已发 |
| v2.3.3 | 生词去重 + 复习/听写整链路测试 | 已发 |
| **v2.4.0** | 用户实测 10 条反馈**全部落地**(识图重做、原型备注、出现次数、助理独立窗口、浅色对比度、材料中心原文优先…) | 已发 |
| **v2.5.0** | 排 bug + 前端大升级(三批)+ 材料中心三修 + 开屏/退出动画 | 已发 |
| **v2.6.0** | 用户 9/28 实测 **11 条**(识图重做 / DeepSeek V4.1 适配 / 材料中心 AI 检索 / 阅读器翻译与点词 / UI 8 条) | 已发 |
| **v2.7.0** | 用户 9/29 实测 **6 大条(11 点)**:输入页几何统一 / 材料中心大修(双动作·中文标题·搜索框·三通道导入) / 上传分析材料 + 外链导入 / 难度自选 i+1·i+10·i+100 / 个性化找资源 / 学习材料整组删除与归类 bug | 已发 |
| **v2.8.0** | 用户 10/1 实测 **10 大条**:识图追加图片闪退修复 / 中文批注合并 / 询问 AI 过渡 / 复习卡住与单词截断 / 学习助理重做(四方向+访谈+对话管理) / 材料中心图文卡片与流式检索 / 输出拼写与翻译练习 / 追问配色 / 我的名片 / 收藏夹四分类 | **已发 = Latest** ✅ |

### 2.2 v2.5~v2.8 提交地图(都在远端了)

```
# v2.8(用户 10/1 的 10 大条)
0bee43e fix(v2.8-B1): 10/1 反馈里的崩溃与硬 bug 七条
60230bb feat(v2.8-B2): 材料中心视觉与信息架构大升级 + 检索流式过程
2668d1a feat(v2.8-B3): 学习助理重做 — 对话管理 + AI 主导的提问式沟通
6e04961 feat(v2.8-B4/B5): 输出练习扩展 + 我的名片 + 收藏夹分类
# v2.7(用户 9/29 的 6 大条)
047ee65/46c93bc/e27af94 feat(v2.7-A/B/C): 输入页几何 + 材料中心大修 + 上传分析材料
ca32381/4fb72f8/66ddd04 chore/test/docs: v2.7.0 发版 + 归档 + 测试
# v2.6(用户 9/28 的 11 条)
de35e32/1f7cd34/dc8b75f/d93871f/01175d0/98ec112
# v2.5
26c5637/8c120f7/6473606
```

> ⚠️ 远端提交的 SHA 与本地**不同**(远端由 API 逐 blob 造提交)。判断"是否同步"要看
> **tree**,不是 SHA:`git rev-parse 'HEAD^{tree}'` 与
> `gh api repos/820sz/ai-shangwaiyu/commits/master --jq .commit.tree.sha` 相同即已同步。

### 2.3 本轮任务状态一览

| # | 任务 | 状态 | 关键产物 |
|---|---|---|---|
| **M1** | 材料中心「AI 找不出任何原版材料」 | ✅ 完成 | `lib/services/original_search.dart` 重写;Gutenberg 站内检索 + arXiv https + 默认热门书单;并行 12s 预算;每源如实报「通/不通/几条」 |
| **M2** | AI 改写看不到出处/来源/思考 | ✅ 完成 | `recommendations` 表加 `model`/`reasoning`(**dbVersion 13**);详情页新增 AI 溯源卡 |
| **M3** | 开屏 + 退出动画 | ✅ 完成 | `splash_screen.dart` / `splash_settings.dart` / `widgets/exit_prompt.dart`;文案在「我的 → 外观」改 |
| **U1** | 设计系统 + 两个首页 | ✅ 完成 | `lib/config/design_tokens.dart`、`lib/widgets/app_ui.dart`、主题统一、`tutor_home.dart` + `input_home.dart` 重排 |
| **U2** | 材料中心 / 阅读器 / 写作 | ✅ 完成 | 见 §3.1 开头;新增 `lib/services/reader_settings.dart` |
| **U3** | 复习 / 我的 / 设置 | ✅ 完成 | 见 §3.2 开头 |
| **P2** | 继续排 bug | ✅ 完成 | 备份恢复丢 `reps`/`lapses`、~90 处写死色收敛、7 处文案星号、analyzer 24→11 |
| — | 发版 v2.5.0 | ✅ 已发 | Release v2.5.0 = Latest,digest `83e2da66…e81f` 已核对 |

---

## 3. 本轮工作明细(已全部完成,保留作背景)

> **U1–U3 的边界(用户拍的)**:只做**排版 / 层级 / 组件统一 / 动效**,**不改业务逻辑**。
> 每批做完必须:analyze 0 error、全量测试绿、**单独 commit**(中文说明)。

### 3.1 U2 — 材料中心 / 阅读器 / 写作 ✅ 已完成(2026-09-27)

**交付摘要**(细节见 `docs/TASK-BOARD-2.5.md` 的「U2 实际交付」):
- 材料中心 / 方向页:全量换成设计系统组件(区块标题、卡片、空态、加载态、错误态);源状态 = 色点 + 一句话;失败卡可一键换源;**顺手修掉界面上漏出来的字面 `**星号**`**。
- 阅读器:**新增阅读设置**(`lib/services/reader_settings.dart`:字号 5 档 / 行距 3 档 + 实时预览,Hive 持久化,**材料阅读器与文章阅读器共用**);查词面板层级重做(词/音标/朗读 → 词性/释义 → 例句卡 → 整行「收进生词本」);失败可原地重试。
- 写作页:编辑/结果两态排版统一;新增**语义色** `AppTheme.successColor / warningColor / dangerColor`(随明暗切换、过 WCAG 闸门),替换写死的 `Colors.green/orange/red`;错误分类标签改用调色板角色。
- 验证:analyze **0 error / 0 warning**;**707 测试全绿 + 1 skip**(新增 `test/reader_settings_test.dart` 12 例 + 语义色对比度闸门)。
- **下面的 a)–d) 是当时的计划,已全部落地**,保留作背景与后续参考。

**a) 材料中心 `lib/screens/input/material_center_screen.dart`(642 行)**
- 现状:源 chips 条 + 内容区 + AI 方向卡网格 + 错误卡,间距/圆角/字号各写各的。
- 要做:页面改用 `Insets.page`;源状态条用 `AppCard` 包一层,「通/不通」用色点 + 文案一眼可见(不是纯文字堆);错误卡换成 `AppErrorCard` + 换源 chips;AI 方向卡网格统一圆角 16 / 间距 12;空态用 `AppEmpty`;列表入场用 `AppStagger`。
- 判据:整页只用 `design_tokens.dart` 的间距/圆角常量,不再出现裸 `EdgeInsets.all(13)` 之类;深浅色各看一眼。

**b) 方向页 `lib/screens/input/category_material_screen.dart`(有 TabBar:资料原文 | AI 整理编写)**
- 要做:Tab 切换后列表排版统一;`_buildHitCard`(原文命中卡)用 `AppCard` + 「原文 · 来源」徽章层级化(标题→作者→来源→动作);`_notes`(每源通/不通)从裸文字改成小字提示条;进页自动搜索的加载态换 `AppLoading`;无结果换 `AppEmpty`(并告诉用户"换英文关键词")。

**c) 阅读器 `lib/screens/input/material_reader_screen.dart`(612 行,含 `_TappableText`/`_WordSheet`)**
- 要做:①阅读区**字号/行距**设置(阅读设置面板,`_WordSheet` 之外的浮层);②查词面板 `_WordSheet` **层级**:词 + 音标头部大一号 → 释义分组 → 例句 → 底部动作按钮(加入生词本 主按钮);③顶部/底部工具条统一到 `Insets.tile`;④长按选词/点击查词的反馈动效统一 `Motion.tap120`。

**d) 写作 `lib/screens/writing/write_review_screen.dart`(967 行,`_Phase{compose,transcribing,reviewing,result,error}`)**
- 要做:五个阶段的版式统一(同一套标题层级 + 同一套卡片);错误态用 `AppErrorCard`(带重试);结果态按钮主次分明;阶段切换加 `AnimatedSwitcher`(250ms,`Motion.transition220` 一类)。

### 3.2 U3 — 复习 / 我的 / 设置 ✅ 已完成(2026-09-27)

**交付摘要**(细节见 `docs/TASK-BOARD-2.5.md` 的「U3 实际交付」):
- 复习页:进度**一眼可读**(大字号当前序号 + 粗进度条 + 「还剩约 N 分钟」);卡片放大且内容垂直居中;评分按钮改**大按钮**(52 高 / FittedBox 防 2× 字号溢出);标记按钮加高到 64;空 / 加载 / 失败态换统一组件(失败可原地重试)。
- 「我的」:13 个平铺入口按**学习 / 数据与回顾 / 设置与数据管理**三组重排,组标题 `AppSectionTitle`、入口统一 `AppActionTile`;顶部数字卡改用语义色。
- 设置四页(API / 外观 / 学习偏好 / 备份):`Insets.page` + `AppSectionTitle` + `AppCard` + `Gap` 统一,底部主按钮 48 高;`AppActionTile` 新增 `enabled`(忙碌中置灰可见)。
- **四个全 App 唯一取色入口**:`AppTheme.masteryColor`(新词/学习中/已掌握)、`wordTypeColor`(单词/短语/句子)、`chartSeries`(图表蓝,明暗两档都达标且保住原色调)、`readableOn`(品牌色在深色下只提亮度到 3:1,不动色相)。
- 验证:analyze **11 条存量 info(0 error / 0 warning)**;717 测试全绿 + 1 skip;43 文件 +1518/−884。

**下面的 a)–c) 是当时的计划,已全部落地**,保留作背景。

**a) 复习页 `lib/screens/review/review_screen.dart`(1465 行,`ReviewCardMode` 枚举)**
- 要做:**大卡片、大按钮**;进度(第 N / 共 M)与剩余时间/待复习数**醒目**(顶部一行大字 + 细进度条);四个评分按钮(Again/Hard/Good/Easy)尺寸与颜色对比拉开;卡片翻转动效统一;空态(今天复习完)用 `AppEmpty` + 一句激励。

**b) 「我的」`lib/screens/profile/profile_home.dart`(506 行)**
- 现状:**13 个 `_MenuTile` 平铺**(我的生词本 / 复习模式 / 学习统计 / 本周报告 / 错误档案 / 备份与导出 / 收藏夹 / API 设置 / 学习偏好 / 外观 / 桌面小组件 / 诊断信息 / 检查更新)。
- 要做:按三组分组,`AppSectionTitle` 做组标题:
  - **学习**:我的生词本、复习模式、收藏夹
  - **数据与回顾**:学习统计、本周报告、错误档案、备份与导出
  - **设置与数据管理**:API 设置、学习偏好、外观、桌面小组件、诊断信息、检查更新
- 顶部三个统计卡(`总词汇量/连续天数/已完成练习`)统一到 `AppCard`。

**c) 设置类页面表单统一**:`api_settings.dart`(582)、`learner_preferences_screen.dart`(360)、`appearance_screen.dart`、`backup_screen.dart`(354)
- 要做:统一"分组卡片 + 行内表单"(标签在左/说明在下、输入框描边用 `scheme.outline`)、保存按钮位置一致、保存成功反馈一致(Toast/SnackBar 同一套)。

### 3.3 P2 — 继续排 bug ✅ 已完成(2026-09-27)

- ✅ **备份恢复丢 `reps`/`lapses`**:`upsertWordReview` 增加恢复模式(传值 = 绝对值写入,不传 = 累加);恢复路径写回复习次数/遗忘次数;新增 2 例测试(含"累加语义没被破坏"的回归)。`test/backup_restore_test.dart` 7 例全绿。
- ✅ **全 App 语义色收敛(浅色"看不清"根治)**:20+ 文件 / 约 90 处写死 `Colors.orange/green/red/blue/amber`(白底 2.2~2.8:1)换成随明暗切换的语义色。**刻意保留**的写死色及理由都写在代码里:图片角标黑白、Android 裁剪页工具栏常量、AI 厂商品牌色板(改由 `readableOn` 提亮)、桌面小组件仿真预览面板。
- ✅ **7 处界面文案里的字面 `**星号**`** → 「」;新增 `test/ui_copy_lint_test.dart` 闸门(只扫字符串字面量,不误伤 `///` 文档注释里的 Markdown)。
- ✅ **analyzer info 24 → 11**(清掉 if 缺大括号 / 多余 import / 插值大括号 / 文档注释 `<...>`);余下 11 条全是存量的 `use_build_context_synchronously`,**刻意不动**(改它容易改出新逻辑)。
- ✅ 复习页 2× 系统字号防溢出。
- **还没做/不适合自动化的**:真机上的观感与手感(尤其新排版在小屏 + 2× 字号、深色下的表现)—— 只能等用户复测反馈。

---

## 4. 代码地图(接手先看这些)

### 4.1 本轮新增/重写的文件

| 文件 | 作用 |
|---|---|
| `lib/config/design_tokens.dart` | **设计令牌唯一事实源**:`Gap`(4/8/12/16/24/32)、`Radii`(control10/card16/sheet20)、`Motion`(tap120/transition220/enter420 + 曲线)、`Insets`(page/card/tile) |
| `lib/widgets/app_ui.dart` | **通用组件**:`AppCard` `AppSectionTitle` `AppActionTile` `AppEmpty` `AppLoading` `AppErrorCard` `AppStagger`(错峰入场 40ms/index,上限 240ms)。**只管外观/结构** |
| `lib/services/original_search.dart` | 原版材料检索:Gutenberg 站内检索页解析 / arXiv / RSS;并行 + 12s 预算;每源 note;跳过已知不可达源 |
| `lib/services/reader_settings.dart` | **阅读设置**(U2):字号 5 档 / 行距 3 档 + 夹档容错;材料阅读器与文章阅读器共用 |
| `lib/config/theme.dart` 的 `successColor/warningColor/dangerColor` | **语义色**(U2):随明暗切换的成功/警告/危险,替换写死的 `Colors.green/orange/red`(过 WCAG 闸门) |
| `lib/services/material_source_status.dart` | 各源健康度(Hive 持久化)+ `preferredSourceId` |
| `lib/services/vision_guard.dart` | 识图结果的**本地确定性校验**(丢空/太短/非英文/截断/复读;同词不同行合并成 occurrences) |
| `lib/services/vision_image.dart` | 图片预处理(EXIF 转正 + 长边 ≤2000 + JPEG q88) |
| `lib/services/lemma.dart` | 原型推导(`taming(tame)`),候选必须是词频表里的真词 |
| `lib/models/vocab_occurrence.dart` | 词汇出现记录(书/页/句),`displayFull` 出 `apple(×2)` |
| `lib/services/splash_settings.dart` | 开屏文案 + 退出场景台词 + "今天问过没" |
| `lib/screens/splash_screen.dart` | 开屏动画(logo 淡入放大 700ms + 文案 Interval(0.5,1.0) 淡入上移;可点跳过) |
| `lib/widgets/exit_prompt.dart` | 退出底部弹层(错峰淡入;一天只问一次;`.show(forceAsk:)`) |
| `lib/screens/tutor/tutor_chat_screen.dart` | 学习助理**独立对话窗口**(头像/流式/思考折叠/思考强度) |
| `lib/screens/input/widgets/quick_replies.dart` | 追问快捷回复条(英英词典 / 梳理内容 / 逐句翻译 / 考我一下 / 换个简单说法) |

### 4.2 大文件(改之前先有心理准备)

```
3092  lib/screens/input/process_chat.dart          ← 识图结果页 + 追问抽屉宿主(待拆二期)
2378  lib/services/database.dart                   ← 所有 SQL 与迁移(dbVersion 13)
1465  lib/screens/review/review_screen.dart        ← U3 目标
1116  lib/services/material_source.dart            ← 各源抓取(长超时 90s)
1071  lib/services/doubao_api.dart                 ← 识图 + 提示词
 983  lib/screens/input/widgets/follow_up_drawer.dart
 967  lib/screens/writing/write_review_screen.dart ← U2 目标
```

### 4.3 数据库

`dbVersion = 13`。迁移在 `lib/services/database.dart`,**每次加列必须**:①`dbVersion++` ②`_onOpen` 自检 ③改 `_vocabularyTableSql`/建表语句 ④更新测试里断言 dbVersion 的地方(`test/widget_test.dart` 等)。

### 4.4 测试

55 个测试文件,694 例 + 1 skip。本轮新增:`vision_guard_test`(16)、`vision_image_test`(7)、`vocab_occurrence_test`(9)、`lemma_test`(11)、`quick_replies_test`(6)、`original_search_test`(8)、`material_group_test`(6)、`splash_settings_test`(5)、`learning_flow_test`(4)、`review_flow_test`(6)、`theme_test`(10,**含浅色对比度闸门 + 硬编码色 lint**)。

> `theme_test.dart` 里有硬编码色 lint:禁止 `Colors.grey[…]`、`Colors.black87`、`Colors.<hue>[50|100|200]`、`onSurface.withAlpha(`。改 UI 时踩到会被测试挡下来 —— 这是故意的。

---

## 5. 运行手册

### 5.1 开发/验证

```powershell
cd D:\readflow
$env:FLUTTER_ALREADY_LOCKED = 'true'
flutter analyze --no-fatal-infos
flutter test
flutter test test/vision_guard_test.dart        # 单文件
flutter run                                      # 真机(USB)
```

### 5.2 发版流程(顺序不能变)

1. **bump `pubspec.yaml`** `version: 2.5.0+62`(铁律,忘 bump 会被用户发现)
2. `flutter analyze --no-fatal-infos` → 0 error / 0 warning
3. `flutter test` → 全绿
4. `flutter build apk --release --target-platform android-arm64`
5. `aapt dump badging build\app\outputs\flutter-apk\app-release.apk | Select-String versionName` → 核对
6. `Get-FileHash ... -Algorithm SHA256` 与 Release 资产 `digest` 逐字核对:
   `gh api repos/820sz/ai-shangwaiyu/releases/tags/v2.5.0 --jq '.assets[].digest'`
7. `gh release create v2.5.0 <apk> --title "..." --notes-file docs/release-notes-v2.5.0.md`
8. **归档 mapping**:`build/app/outputs/flutter_release/mapping` → `tool/symbols/2.5.0/`
9. 更新 `PLAN.md` 状态三行 + 追加版本记录小节
10. commit(+ 可选 tag)→ **同步远端**(见下)

### 5.3 同步远端(不走 git push,走 GitHub API 逐 blob)

远端有的提交与我本地的 SHA 不同(远端是 API 造的),所以必须给脚本一个 **diff 基准 = 一个本地提交,它的 tree 等于远端当前 tree**。

```powershell
cd D:\readflow
Set-ExecutionPolicy -Scope Process Bypass -Force
# 1) 查远端当前 tree
gh api repos/820sz/ai-shangwaiyu/commits/master --jq .commit.tree.sha
# 2) 找本地哪个提交的 tree 与它相同(通常就是上一次同步后的本地 HEAD)
git rev-parse 'HEAD^{tree}'
# 3) 设基准后跑脚本
$env:RF_DIFF_BASE = '<那个本地提交>'
& .\tool\push_via_api.ps1        # 注意:本机是 PowerShell 5.1,没有 pwsh 命令
```
成功打印 `PUSH_VIA_API_DONE`;基准猜错会打印 `TREE_MISMATCH_ABORT`(**不会有副作用,换基准重跑即可**)。

> 现成数据(**每次同步成功后要把这几行更新成新值**):
> - 2026-09-27(U2 完成那次):远端 tree `851f8e2f` ↔ 本地提交 `8c120f7`
> - 2026-09-27(v2.5.0 发版):远端 tree `16c8768a` ↔ 本地提交 `e4eb535`
> - 2026-09-28(v2.6.0 发版):远端 tree `c4ef0e1e` ↔ 本地提交 `aa0d0dc`;随后 tree `2b72efbd` ↔ `01175d0`
> - 2026-09-28(v2.6 文档同步):远端 tree `10b0e3d4` ↔ 本地提交 `98ec112`
> - 2026-09-29(**v2.7.0 发版这次**):远端 tree `176c1626` ↔ 本地提交 `66ddd04`
> - 2026-09-29(发版后文档收尾):远端 tree `7499c8f6` ↔ 本地提交 `5cce23d`
> - 2026-09-29(最终):远端 tree `389a058d` ↔ 本地提交 `b315c9b`
> - 2026-10-01(**v2.8.0 发版这次**):远端 tree `e1facc13` ↔ 本地提交 `40d75cd`(基准取 `b315c9b`)
> - 判断方法同上:比对 `git rev-parse 'HEAD^{tree}'` 与远端 `tree.sha`。
>   ⚠️ **文件名不要用中文**:`push_via_api.ps1` 里 `git rev-parse "HEAD:<文件>"` 在中文路径上会被
>   PowerShell 的编码搞成 mojibake,报 `path ... does not exist in HEAD`(v2.8 踩过一次,改名即恢复)。
> - 同步脚本:`Set-ExecutionPolicy -Scope Process Bypass -Force` 后 `& .\tool\push_via_api.ps1`
>   (本机是 **Windows PowerShell 5.1**,没有 `pwsh` 命令,别写 `pwsh tool/...`)。

---

## 6. 环境与网络事实(大陆网络实测)

| 事实 | 值 |
|---|---|
| 可达 | NPR RSS、gutenberg.org(**站内检索 3.1s / 10 条**)、arXiv(**https,6.7s / 10 条**) |
| **不可达/超时** | ❌ `gutendex.com`(**12.5s 超时** — 上一版挑错的就是它)、bbc_le / voa_le / ted / wikipedia(~20s) |
| 结论 | 候选源必须**实测**,不能照文档抄;不可达的源要**如实报"不通"**并记住(跳过),不要静默吞掉 |

其他环境事实:
- 所有 Release **都用 debug keystore 签名**(指纹 `f94a4bec…`)→ 换正式 keystore 会导致老用户**无法覆盖安装**。用户还没拍板,别擅自换。
- 诊断页(`我的 → 诊断信息`)会显示 API Key(打码 + 长度)、材料源健康表、小组件状态 —— **要用户给设备证据时,让他截图这一页最快**。
- 构建/测试必须带 `$env:FLUTTER_ALREADY_LOCKED='true'`。
- 文件策略 danger-full-access;**审批提示已禁用 → 永远不要传 `sandbox_permissions`**。

---

## 7. 坑与教训(踩过的,别再来一次)

1. **PowerShell 改源码 → 中文乱码**。只用 read/edit/write 工具改源码。
   **具体踩法(2026-09-29 又一次)**:`Get-Content` / `Set-Content` **不加 `-Encoding`** 时按系统
   ANSI(GBK)读写 —— 读 UTF-8 源码得到 mojibake,写回就把整个文件毁了(而且不可逆:
   GBK 解码时的非法序列已经变成 `?`)。真需要按行裁剪时,只能用
   `[System.IO.File]::ReadAllText/WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false)))`
   这种**显式编码**的 .NET 调用,并且改完立刻用 read 工具回读确认中文没坏。
   我这次毁了 `material_reader_screen.dart`(926 行)后是靠 `git checkout` 恢复 + 重做全部 edit 挽回的。
2. **`git commit` 消息里有 `"` 会被 PowerShell 吃掉** → 写进临时文件用 `git commit -F <file>`。
3. **`flutter test` 经过 `Select-Object` 管道后 `$LASTEXITCODE` 不可信** → 单独看输出,别只看退出码。
4. **插入代码时误删方法体**(发生过两次)→ 每次 edit 后 `flutter analyze` 立即验。
5. **`Utf8Decoder` 子类型崩溃**(v1.9.0 流式全挂)→ 流处理要 `rawStream.cast<List<int>>()`。
6. **`getRecentMaterials` 用 INNER JOIN** 会藏掉未入库材料,且必须 `m.id AS id`(否则书架条目 id 恒 0 点不开)。
7. **删除文件的目录不会被重建** → `push_via_api.ps1` 已修(把被删文件的父目录也算进去)。
8. **Hive 读回的嵌套 Map 是 `_Map<dynamic,dynamic>`** → 必须 `Map<String,dynamic>.from(...)`,直接 `as` 会运行时炸。
9. **widget 测试坑**:FakeAsync 里等真实磁盘 IO 会挂起(放 setUp);`showModalBottomSheet` 在 widget 测试里不推进(直接 skip 留骨架);`skip:` 只接受 bool。
10. **测试失败先怀疑自己的断言**,不要急着改产品代码(我多次因为断言写错而"修 bug")。
11. **别信"代码推断"**:网络可达性、真机行为、安装链路 —— 一律以实测为准。
12. **第三方插件在 AGP 9 上要真机/真构建验证**(2026-09-29):本项目用 **AGP 9.0.1 + Gradle 9.1 +
   Kotlin 2.3.20 + Flutter 内置 Kotlin**,而 `file_picker 11.0.3` 的 `android/build.gradle` 里有
   `if (!isAgp9OrAbove) apply plugin: 'org.jetbrains.kotlin.android'` —— AGP 9 下它**不 apply
   Kotlin 插件**,可它自己的源码是 `.kt`,于是 Kotlin 源根本不编译,`flutter build apk` 报
   「找不到符号 FilePickerPlugin」。**解法**:锁 `file_picker: 10.0.0`(android 侧是 Java 源码)。
   教训:加依赖后**必须真的跑一次 `flutter build apk`**,`flutter analyze` 与 `flutter test`
   都过了也不代表能构建。

---

## 8. 等用户真机复测的清单

**v2.8.0 已发出**(Release Latest,digest 已核对),现在等用户真机复测:

**v2.8.0(本次,用户 10/1 的 10 大条)**:
- **识图「追加图片」**:连续追加 2~4 张不再闪退;追加失败时旧结果仍在(有明确提示);
- **中文材料**:页边中文批注是否并进了英文词条(卡片上一行「页边批注」),不再出现
  同一内容两张卡、且都是英文当头;
- **点「询问 AI」**:弹层与讲解是否"有过渡"(三点动画/骨架条/内容淡入);
- **复习**:从下一张退回再点「认识」是否往下走;长单词(primordial 这种)是否还拆行;
- **学习助理**:①「先聊两句」6 步访谈(点选项)+ 答完是否体现在"现状分析/学习任务"里;
  ②对话管理:新建/历史/改标题/清空/删除;③「让 AI 排规划」「看我最薄弱的」带问题进对话;
  ④AI 反问时是否给了可点选项;
- **材料中心**:图文卡片与「今日精读」大卡;题材 tab 与三路并行检索;
  **流式「查阅了 xxx」**;分类页右上角「跟 AI 说需求」;逐段翻译是否"滚到哪翻到哪";
- **输出**:词汇拼写 / 翻译练习(错题是否进了今天的复习);目标卡是否影响题量;
  口语占位说明是否讲清;
- **我的**:个性化名片(相册头像/文字头像/背景/签名/词汇量);
- **收藏夹**:四个分区 chip 是否好用、AI 材料与写译批改的收藏是否落到对应分区。

**更早版本(如仍未复测)**:识图对账数字与「待确认」、材料中心三通道导入、
上传分析材料与外链导入、阅读器底部动作栏、学习材料分组删除与归类。

> 拿到反馈后的规矩不变:**只做他列的事**、不清楚先问、每批量做完再报、发版前 bump 版本号。
>
> ⚠️ **待用户拍板**:材料配图走 ①程序化封面(已做)②AI 生图(≈0.1 元/篇)③自购插画库。

---

## 9. 接手自检(第一步就做这些)

```powershell
cd D:\readflow
git log --oneline -6                     # 确认 HEAD 是 v2.5.0 发版提交或它的后继
git status --porcelain                   # 期望干净
$env:FLUTTER_ALREADY_LOCKED='true'
flutter analyze --no-fatal-infos         # 期望 0 error / 0 warning(11 条 info 是存量)
flutter test                             # 期望 717 全绿 + 1 skip
gh release list --limit 3                # 期望 v2.5.0 为 Latest
```

当前状态:**v2.5 的五件事已全部交付并发版,没有待办开发任务**。

接到用户新反馈/新需求时,按老流程走:
1. **先问清楚**(不清楚的不要猜),把用户原话逐条抄进一张新的任务板 `docs/TASK-BOARD-<日期>.md`;
2. 按优先级分批做,**每批做完 analyze + 全量测试 + 单独 commit + 汇报**;
3. 发版走 §5.2 的步骤(bump → analyze → test → build → aapt 验版本 → release → 核对 digest → 归档 mapping → 更新 PLAN);
4. 同步远端走 §5.3(`RF_DIFF_BASE` = tree 与远端相同的那个本地提交)。

**每完成一批就 commit + 汇报**,不要攒到最后。
