# 交接文档 · 给下一个对话(2026-10-07 写,v2.11.0 发版后)

> 这份是**给人看的一页纸**。更细的历史在 `PLAN.md` / `docs/HANDOFF-2.5.md` / 各批次任务板里,
> 本文只写"接手时你必须知道的事",不重复那些。

---

## 0. 一句话现状

**v2.11.0 已发布、远端已同步、工作区干净。用户 10/5 提的 4 条全部交付。
唯一悬着的是 `profile_card_test.dart` 里 1 条界面用例的假失败(测试环境问题,与 App 无关),
以及用户在真机上的复测结果。**

| 项 | 值 |
|---|---|
| 版本 | `pubspec.yaml` → **2.11.0+68** |
| Release | **v2.11.0**(含 `app-release.apk`,26,763,536 B) |
| APK sha256 | `6358c5330cc579d4bde5747b87b419c99a2624e57d92989e8a1d142ad9e98e0b` |
| release digest | `sha256:6358c533…9e98e0b` —— **与本地逐字一致** |
| 本地提交 | `008873c`(之后又跑了同步,未产生新提交);本地 tree `19bf0ef1…` |
| 远端 | master = `fad8fe1db793bfc5cccd80824c1f5130e60b2785`,tree `19bf0ef1…`(**与本地一致**) |
| 绿灯 | `flutter analyze` **0 error / 0 warning**(11 条存量 info) |
| 全量测试 | **1043 passed + 1 skip + 1 failed**(跑三遍结果一致;失败项见 §5) |
| 数据库 | **dbVersion 18**(新增 `materials.cover_url`) |
| 依赖 | **零新增**(封面/动效全部自写,没引入 cached_network_image 等) |

---

## 1. 事实源

| 文件 | 管什么 |
|---|---|
| `PLAN.md` 顶部三行 | **版本号 / 阶段的唯一事实源**(每次发版必须同步改) |
| `docs/HANDOFF-2.5.md` | 交接主文档:命令、坑、提交地图、§8 复测清单 |
| `docs/release-notes-v2.11.0.md` | **本次**给用户看的更新说明(也是发给他的口径) |
| `docs/TASK-BOARD-2026-10-04.md` | 上一批(8 条)的用户原话 + 根因表 |
| `C:\Users\xi283\.dsh\memory\readflow-dev-session.md` | 跨会话记忆(教训都在里面) |

---

## 2. 铁律(用户明确要求过,违反会被骂)

1. **只做他列的事** —— 不顺手改别的功能。
2. **核心功能出问题:先把现有实现摊开 + 根因分析,再动手**。他最反感"不回答问题直接改代码"。
3. **涉及全 App 视觉/交互的大改,先给 2~4 个方案让他选**(原话:"不确定的就给我推荐几个方案")。
4. **每批做完报一次**;**先回话,再干活** —— 他催进度时如果还在跑命令/等后台任务,会被视为"卡死"。
5. **禁止自杀式操作**:不要 taskkill / 杀 node / 杀 3080(那是他 DSH 服务本体)。
6. **禁止用 PowerShell 文本命令改源码**(`Set-Content` / `Get-Content|Out-File` / `-replace`),
   只用编辑器工具(read/write/edit)。中文必须 UTF-8。(曾把整个文件写成 mojibake,不可逆)
7. **发版前必须 bump 版本号**;发布后核对 APK 的 sha256 与 release asset digest 一致。
8. **不要新增 pub 依赖**(`file_picker` 那次:analyze/test 全绿,APK 构建不过)。
9. **界面里不许出现 `CircularProgressIndicator`**(已改成 `lib/widgets/waiting.dart` 的三件套;
   唯一例外是音频缓冲条)。**注意:目前仍有 24 处裸转圈没清完**,属于已知待办。
10. **一排按钮必须能换行** —— 用 `Wrap` + 紧凑样式,不要无约束的 `Row`。
    **同类坑新实例**:固定高的横滑卡里用 `Column + Spacer` 会在系统大字号下溢出 ——
    文字区要 `Expanded` 包住(见 `_buildFeedCard`)。
11. 注释写中文,并写清"为什么"。
12. **发版规矩**:验完再发。全量测试 **跑一次就够**(十几分钟),别反复跑;改过代码就要重跑。

---

## 3. 命令(PowerShell 5.1,**没有 pwsh 命令**,所有命令在 `D:\readflow` 下跑)

```powershell
$env:FLUTTER_ALREADY_LOCKED = 'true'     # 每个新 shell 都要,否则 flutter 卡锁
flutter analyze --no-fatal-infos        # 期望 11 条存量 info、0 error / 0 warning
flutter test                            # 全量:1043 passed + 1 skip + 1 failed(十几分钟,发版前跑一次)
flutter test test/xxx_test.dart         # 改完先跑相关文件
flutter build apk --release --target-platform android-arm64
# 校验 APK:
& 'C:\Users\xi283\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe' dump badging build\app\outputs\flutter-apk\app-release.apk | Select-String versionName
# 发版(gh CLI 已登录 820sz):
gh release create vX.Y.Z build\app\outputs\flutter-apk\app-release.apk --title "..." --notes-file docs\release-notes-vX.Y.Z.md
gh release view vX.Y.Z --repo 820sz/ai-shangwaiyu --json assets   # 看 assets[0].digest 与本地 sha256
# 同步远端(不是 git push!):
Set-ExecutionPolicy -Scope Process Bypass -Force
$env:RF_DIFF_BASE = '<tree 与远端一致的本地提交>'   # 本次是 bd1b437
& .\tool\push_via_api.ps1                            # 打印 PUSH_VIA_API_DONE 才算成功
```

---

## 4. 已知的坑(踩过的,别再踩)

1. **中文文件名会让同步脚本断掉** —— 新文件一律用 ASCII 名。
2. **`edit` 工具的 `old_string` 结尾带换行会静默吞行**,而且**大段替换容易只删掉一小截**:
   本次把 200 多行残留删掉时试了三次都没删干净,最后是**用 write 重写整个文件**解决的。
   教训:要删大段代码,直接重写文件,别跟 edit 较劲。
3. **全量 `flutter test` 十几分钟** —— 别反复跑。
4. **Hive 真实写盘 vs 假时钟**(本次最大的坑,见 §5)。
5. **固定高卡片里不要用 `Column + Spacer`**(会 BOTTOM OVERFLOWED),用 `Expanded` 包住。
6. **`TextButton`/小按钮排在窄卡里必须 `Wrap`**,否则被裁成半个字。
7. **`edit` 大段替换后一定回读确认**(本次有两次把文件改坏,靠 analyze 才发现)。

---

## 5. 唯一未解决事项(测试环境问题,不影响 App)

**`test/profile_card_test.dart` 的 4 条界面用例里,有 1 条会假失败**(全量跑必现,单独跑秒过):

| 现象 | 根因 |
|---|---|
| `下滑关闭弹层 = 什么都不改` 报 `Expected: Size(64,64) / Actual: Size(84,84)` | 上一条用例点过「保存名片」→ `ProfileCardSettings.save()` 是 `await box.put(...)` 的**真实写盘**,测试跑在**假时钟**里,那次写永远悬在 Hive 队列上;下一条用例开头 `clear()` 排队等它 → 超时被跳过 → 读到上一条的 84 |

**已经做过的(5 种都不稳,别再重复试)**:
`setUp` 里直连 `clear()` / `runAsync` 包 clear / `deleteBoxFromDisk` 重开 box /
真时钟空转 50ms / 把界面用例拆到另一个文件。**根因是"假时钟 vs Hive 写队列"的对冲**,
不是清理写法。目前只给它加了 **3 秒上界**(不再无限挂,10 分钟 → 14 秒)。

**彻底修法(独立排期,要改产品代码)**:把 `ProfileCardSettings` 的存储抽成**可注入接口**
(Hive / 内存两套实现),测试用内存实现 → 零真实 I/O,这个坑连根消失。

---

## 6. 下一步(按优先级)

1. **等用户真机复测 v2.11.0**,重点四样:
   **① 材料能不能打开**(他截图那条"书籍 id 不合法:0");**② 封面有没有真图**
   (今日推荐横滑卡 + 书架"查看封面" + 材料库);**③ 材料中心观感**
   (主角卡 / 3 组分段切换 / 真书架 / 横滑推荐);**④ 名片签名颜色是否分得开**。
2. 两个**等他拍板**的事(他还没回):
   ① **公版书"真原插图"按需入口** —— 真插图在 `<id>-h.htm` 的 `images/` 里(实测 650KB、
   偶发 EOF、最长 60 秒),我判断不该进正常打开流程,建议做成"长按封面 → 抓真插图";
   ② **arXiv/维基/外媒的配图**:arXiv 只有自家 logo;Wikipedia/BBC/TED/VOA 当前网络不可达。
3. 积压的清理项:24 处裸 `CircularProgressIndicator` 收敛到 `waiting.dart` 三件套。
4. 反馈回来后的规矩照旧:**只做他列的事 → 先摊开分析 → 每批报一次 → bump → 验 → 发版 → 同步 → 文档+记忆**。

---

## 7. v2.11.0 这一批做了什么(v2.10 以来的变化)

| 用户原话(10/5) | 根因 | 交付 |
|---|---|---|
| "材料中心存在部分文章打不开"(截图:`书籍 id 不合法:0`) | `openHit` 写死 `int.tryParse(sourceId2) ?? 0`;而"今日推荐/今日精读"的 `sourceId2` 是 **RSS 的整条 URL** → 得 0 → `fetchGutenberg(0)` 抛错。仓库里早有 `gutenbergIdOf()` 能用,只是这条链路没用上 | 新增可测纯函数 `normalizeSourceId2` / `hitFetchPlanFor`,`openHit` 按源规范化;分类页那颗同类 `int.parse` 一并修;红→绿→撤修复再红→恢复绿走完 |
| "把原材料的原插图作为材料的封面"(明确否掉 AI 生图) | ① `imageOf` 只认 media RSS(NPR 实测 0 命中);② 文章页 `og:image` 全库无实现;③ **拿到了也不落库** | RSS 内嵌 `<img>` 兜底(单引号 + 滤追踪像素)/ `og:image` CDN 拆包(NPR 直连 403)/ 公版书按书号现算 / **DB 18 `cover_url` 落库** / 补 3 处漏传 imageUrl 的调用点 / `cacheWidth` 限制解码 |
| 名片:签名与名字要有区分度、删掉圈起来的描述、编辑界面约 1 屏 | 名字与签名**都是白色**只差透明度;卡上那句描述与宽按钮占版面;弹层里 `maxLength` 计数器/说明文案/分组标题把高度吃掉 | 签名改冷青灰 `#CFE3E8`;删描述与宽按钮,入口改右上角小铅笔(34×34 + Semantics 标签);弹层压到约 1 屏(三组 chip 合并、计数器改 `inputFormatters`) |
| 全局 UI 大升级(B + A 材料中心) | 体检:`AppCard` 是全 App 唯一容器**没有型号**(约 51 处)、`AppActionTile` 一种版式用 20 次、全库 `GridView`/`Hero`/`PageView` **0 处**、字号手写散落 | `AppFont` 5 档字阶 + `AppCard` 4 变体 + `AppActionTile` 网格版式;材料中心:主角卡置顶 / 真 `GridView` / 横滑推荐卡 / **复用真 `BookshelfView`** / 3 组分段切换;底栏轻动效(指示条 + 微缩放 + 触觉) |

**新增测试**:`test/cover_source_test.dart`(17 条)、`test/app_ui_variants_test.dart`(9 条);
全量从 v2.10 的 961 条涨到 **1043 条**。
