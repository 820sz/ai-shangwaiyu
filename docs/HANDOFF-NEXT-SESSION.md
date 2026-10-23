# 交接文档 · 给下一个对话(2026-10-23 写,v2.12 前端全面升级后)

> 一页纸。细节在 `PLAN.md` / `docs/FRONTEND-UPGRADE-PLAN.md` / `docs/HANDOFF-2.5.md`。

---

## 0. 一句话现状

**v2.12.0 前端全面升级第一批已发布、远端已同步、工作区干净。等用户真机验收视觉,
然后再做第二批(收藏夹/统计/设置/阅读器/今日推荐横卡换形态),并处理已知测试假失败。**

| 项 | 值 |
|---|---|
| 版本 | `pubspec.yaml` → **2.12.0+69** |
| Release | **v2.12.0**,APK 26,763,608 B |
| APK sha256 | `0fe4cd28e3f904e31d035616111e6b08c430ce24c44b7aabeb083ff027c5baef` |
| release digest | `sha256:0fe4cd28…7c5baef` —— **与本地逐字一致** |
| 远端 | master = `cf2c0a14a06305b2f254fb707416fc74c6410f9c`,tree `596690b5…`(**与本地一致**) |
| 绿灯 | `flutter analyze` **0 error / 0 warning**(11 条存量 info) |
| 全量测试 | **1044 passed + 1 skip + 1 failed**(失败项 = 已知 Hive 假失败,下同) |
| 数据库 | dbVersion **18**(未变) |
| 依赖 | **零新增** |
| 本批提交 | `767fa47`(设计系统+组件库+输入页+材料中心)/ `66b9b9d`(输出/我的/助理/书架3D)/ `8b7070f`(转圈清零+底栏+分类页)/ `b294a6e`+`b0c6f84`(bump 与文档) |

---

## 1. 用户这次的原话与原则(2026-10-23,最重要)

> 「**精简和高级、实用是第一位**,在此基础上,去增加软件前端的**丰富性和趣味性**,
> 让使用体验过程不单独枯燥!」
> 「**整个软件的前端都需要升级,不只是 ui,各方面的交互、分类逻辑等等都要,不限于**」
> 「做好任务记忆管理与规划…做好调研学习与前端工作,开工」

他给了 **5 张样图**(扇贝阅读每日精读/发现更多、训记商店页、轻小说文库×2)作为需求证据,
并明确:**不要照抄表面,学本质**。

### 从样图提炼、并已落进代码的"本质"
1. **一个内容单元 = 通栏图 + 标签行 + 标题 + 元信息 + 整宽主按钮**(→ `AppHeroCard`);
2. **列表用左文右图横卡 + 竖排 Lv 徽标**(→ `AppWideCard`);
3. **分类 tab 用内容领域**(→ 复用仓库里早就有的 `MaterialTopic.all`);
4. **3D 书架**由透视与纵深营造,不一定要真转盘(→ `Matrix4..rotateX`);
5. **杂志式编号小标**(→ `AppSectionHeader(indexLabel: '01')`)。

---

## 2. 铁律(违反会被骂)

1. **只做他列的事**;核心功能出问题:**先摊开现有实现 + 根因**,再动手;大改**先给 2~4 个方案**让他选。
2. **先回话再干活**;每批做完报一次;催进度时不要还在跑命令。
3. **禁止自杀式操作**(taskkill / 杀 node / 杀 3080 —— 那是他 DSH 本体)。
4. **禁止用 PowerShell 文本命令改源码**;只用 read/write/edit;中文 UTF-8。
5. **发版前 bump**;发布后核对 APK sha256 == release asset digest;**验完再发**。
6. **不新增 pub 依赖**(加了要真跑 `flutter build apk`)。
7. **界面里不许出现 `CircularProgressIndicator`** —— **v2.12 已清零**(唯一例外:音频缓冲条)。
8. **一排按钮必须能换行**(`Wrap`);固定高卡片里文字区用 `Expanded` 包住(`Column+Spacer` 会 BOTTOM OVERFLOWED)。
9. 注释写中文,写"为什么"。
10. **前端改动分屏批做**:每批跑相关测试 + `flutter analyze`,最后全量一次。

---

## 3. 命令(PowerShell 5.1,在 `D:\readflow`)

```powershell
$env:FLUTTER_ALREADY_LOCKED = 'true'     # 每个新 shell 都要
flutter analyze --no-fatal-infos        # 期望 11 条存量 info、0 error/0 warning
flutter test                            # 全量 1044 passed + 1 skip + 1 failed(十几分钟,发版前跑一次)
flutter test test/xxx_test.dart         # 改完先跑相关文件
flutter build apk --release --target-platform android-arm64
& 'C:\Users\xi283\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe' dump badging build\app\outputs\flutter-apk\app-release.apk | Select-String versionName
gh release create vX.Y.Z build\app\outputs\flutter-apk\app-release.apk --title "..." --notes-file docs\release-notes-vX.Y.Z.md
gh release view vX.Y.Z --repo 820sz/ai-shangwaiyu --json assets   # 看 assets[0].digest
# 同步远端(不是 git push!):
Set-ExecutionPolicy -Scope Process Bypass -Force
$env:RF_DIFF_BASE = '<tree 与远端一致的本地提交>'
& .\tool\push_via_api.ps1                # 打印 PUSH_VIA_API_DONE 才算成功
```

---

## 4. 设计系统 v2 速查(新代码必须用它,不许写裸数值)

| 类别 | 文件 | 关键值 |
|---|---|---|
| 颜色 | `config/theme.dart` | 浅色暖白 `#FDFCF9` / 主色蓝 `#1F63D8` / 墨黑 `#14161A`;深色 `#0F1115` / `#171A20` / `#1F232B` / 亮蓝 `#7FA8FF` |
| 字阶 | `config/design_tokens.dart` `AppFont` | display 28 / title 22 / heading 18 / subhead 16 / body 14.5 / meta 12 / tag 11(各带行高字距) |
| 圆角 | `Radii` | control 12 / card 20 / hero 24 / sheet 24 / pill 999 |
| 阴影 | `AppShadow` | 只 2 档 `sm`/`md`,**深色返回空** |
| 间距 | `Gap` | 4/8/12/16/20(page)/24/32/48 |
| 卡片 | `widgets/app_ui.dart` `AppCard` | 4 变体 plain/compact/hero/accent;Material+Container 真阴影 |
| 形态件 | `widgets/design_kit.dart` | `AppHeroCard` / `AppWideCard` / `AppTag` / `AppLevelBadge` / `AppSectionHeader` / `AppContentTabs` / `AppMeta` / `AppStat` / `AppProgressRing`(自绘)/ `AppEmptyState`(自绘)/ `AppPressScale` |

---

## 5. 已知的坑(踩过的)

1. **改嵌套结构(加 SafeArea/包一层)时,括号极易错位** —— 本轮我踩了 3 次,每次靠 `flutter analyze` 才抓到。
   **改完立刻单独 analyze 该文件**,别等最后。
2. **大段删代码别跟 `edit` 较劲** —— 直接 `write` 重写文件(上次的教训)。
3. **Hive 真实写盘 vs 假时钟**:`profile_card_test` 的界面用例点过"保存名片"后会悬一次写,
   下一条用例 `clear()` 排队等它 → 已知假失败(已加 3 秒上界)。**别再重复试清理写法**;
   根治 = 把名片存储抽成可注入接口(独立待办)。
4. **"分类逻辑"类抱怨,先查仓库里有没有现成的分类数据模型** —— 本轮发现
   `MaterialTopic.all`(科学与技术/商业与政治/…)v2.8 就写好了、还注释着"参考软件顶部就是这种 tab",
   却一直被埋在折叠区里的多选 chip 后面。**用户要的东西可能早就在仓库里。**
5. **"丰富"≠"换排列"**:上一轮我加网格/横滑/分段,用户仍说"毫无变化" —— 因为**形态**没变。
   这一轮引入"大图卡/横卡/3D 书架/数据面板"才算形态变化。
6. **`theme_test.dart` 的硬编码闸门**会抓 `onSurface.withAlpha(...)` 这类写法;
   要淡色文字用 `AppTheme.faintText(context)`。

---

## 6. 下一步(按优先级)

1. **等用户真机验收 v2.12 这批视觉**(重点:整体配色/字号是否"高级"了、材料中心内容领域页签
   分类是否说得通、横卡扫读、书架 3D、底栏新文案)。**他确认后再发版**。
2. 发版流程:全量测试(已跑)→ 构建 APK(已构建,本轮)→ 报告 → 他点头 → `gh release create`
   → 核对 digest → 同步远端 → 更新文档与记忆。
3. **第二批视觉(未做)**:
   - 收藏夹 / 统计页 / 设置类页面的卡片形态统一(本批只清了它们的转圈);
   - 阅读器视觉(只跟随了新主题,未重排);
   - 材料中心「今日推荐」横滑卡还是旧版式 → 换 `AppWideCard` 或新横滑卡;
   - 学习助理页的首屏(仍是 AppBar,未改成大标题)。
4. 独立技术债:名片存储抽可注入接口(根治 Hive 测试假失败)。

---

## 7. 本批(v2.12)做了什么

| 批 | 内容 |
|---|---|
| ① 设计系统 v2 | 暖白+蓝主色 / 7 档字阶 / 新圆角体系 / 两档真阴影 / AppCard 重写成 Material+Container |
| ② 组件库 `design_kit` | 大图 Hero 卡、左文右图横卡、胶囊标签、横竖 Lv 徽标、编号区块标题、内容领域页签、自绘圆环、自绘空态、按压缩放 |
| ③ 输入页 | 去 AppBar → 大标题 + 日期;主行动卡 hero 化;整宽主按钮;材料中心入口降为入口条 |
| ④ 材料中心 | 删掉自编三组分段;顶部**内容领域页签**(MaterialTopic);杂志流;材料库改横卡 |
| ⑤ 输出/我的/助理 | 大标题/编号区块;数字合并成数据面板;助理清转圈 |
| ⑥ 书架 | 加轻微 3D 透视(`Matrix4..rotateX(0.045)`) |
| ⑦ 底栏 | 文案用户语言:材料 / 练习 / 我的 / 助理 |
| ⑧ 转圈清零 | **21 处**全部换成 `SkeletonLines`/`ThinkingDots`/`AppLoading`/`ProgressStageBar`/自绘 `AppProgressRing` |
